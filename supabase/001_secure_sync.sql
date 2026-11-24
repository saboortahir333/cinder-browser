-- ============================================================================
-- Cinder Browser - secure cloud sync schema (migration 001)
--
-- WHY THIS EXISTS
--   The previous schema (supabase_bookmarks_table.sql / supabase_settings_schema.sql)
--   used `USING (true)` policies and nullable user_id. Because the anon key ships
--   inside the app, ANYONE could read/delete EVERY user's history, bookmarks and
--   settings. This migration removes those policies and replaces them with
--   per-user Row Level Security plus end-to-end encrypted storage.
--
-- DESIGN
--   * All user data lives in `synced_records` as client-side AES-256-GCM
--     ciphertext. The server (and anyone with DB access) cannot read URLs,
--     titles, tabs, history or settings values.
--   * `user_keys` stores only the *wrapped* (encrypted) master key plus the
--     Argon2id parameters. The sync passphrase never leaves the device.
--   * Every policy is restricted to the `authenticated` role and keyed on
--     auth.uid(). The `anon` role gets no access to user data at all.
--
-- HOW TO APPLY
--   Supabase Dashboard -> SQL Editor -> paste -> Run. Safe to re-run.
--   Before running: Authentication -> Providers -> enable Email, and set
--   "Confirm email" ON. Enable leaked-password protection and a minimum
--   password length of 12 (Authentication -> Policies).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Lock down the legacy plaintext tables (deny-by-default).
--    Rows with user_id = NULL are orphaned test data; export anything you
--    need with the service role, then DROP these tables.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t text;
  p record;
BEGIN
  FOREACH t IN ARRAY ARRAY['bookmarks','browsing_history','search_history','user_settings','downloads']
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      FOR p IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = t
      LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', p.policyname, t);
      END LOOP;
      EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Wrapped key material (one row per user).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_keys (
  user_id                     uuid PRIMARY KEY DEFAULT auth.uid()
                                REFERENCES auth.users(id) ON DELETE CASCADE,
  kdf                         text     NOT NULL DEFAULT 'argon2id' CHECK (kdf = 'argon2id'),
  kdf_salt                    text     NOT NULL CHECK (char_length(kdf_salt) BETWEEN 16 AND 128),
  kdf_memory_kib              integer  NOT NULL CHECK (kdf_memory_kib BETWEEN 19456 AND 1048576),
  kdf_iterations              integer  NOT NULL CHECK (kdf_iterations BETWEEN 2 AND 16),
  kdf_parallelism             integer  NOT NULL CHECK (kdf_parallelism BETWEEN 1 AND 16),
  wrapped_master_key          text     NOT NULL CHECK (char_length(wrapped_master_key) BETWEEN 40 AND 512),
  recovery_wrapped_master_key text     CHECK (char_length(recovery_wrapped_master_key) BETWEEN 40 AND 512),
  key_version                 smallint NOT NULL DEFAULT 1,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_keys FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.user_keys TO authenticated;

DROP POLICY IF EXISTS user_keys_select ON public.user_keys;
DROP POLICY IF EXISTS user_keys_insert ON public.user_keys;
DROP POLICY IF EXISTS user_keys_update ON public.user_keys;
CREATE POLICY user_keys_select ON public.user_keys FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY user_keys_insert ON public.user_keys FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY user_keys_update ON public.user_keys FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- ---------------------------------------------------------------------------
-- 3. Encrypted records (history, bookmarks, session, settings, ...).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.synced_records (
  user_id        uuid        NOT NULL DEFAULT auth.uid()
                               REFERENCES auth.users(id) ON DELETE CASCADE,
  profile_id     text        NOT NULL DEFAULT 'default'
                               CHECK (profile_id ~ '^[a-z0-9_-]{1,32}$'),
  kind           text        NOT NULL CHECK (kind ~ '^[a-z_]{1,32}$'),
  record_id      text        NOT NULL CHECK (char_length(record_id) BETWEEN 1 AND 128),
  ciphertext     text        NOT NULL CHECK (char_length(ciphertext) BETWEEN 1 AND 262144),
  schema_version smallint    NOT NULL DEFAULT 1,
  deleted        boolean     NOT NULL DEFAULT false,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, profile_id, kind, record_id)
);

CREATE INDEX IF NOT EXISTS synced_records_kind_updated_idx
  ON public.synced_records (user_id, profile_id, kind, updated_at DESC);

ALTER TABLE public.synced_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.synced_records FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.synced_records TO authenticated;

DROP POLICY IF EXISTS synced_records_select ON public.synced_records;
DROP POLICY IF EXISTS synced_records_insert ON public.synced_records;
DROP POLICY IF EXISTS synced_records_update ON public.synced_records;
DROP POLICY IF EXISTS synced_records_delete ON public.synced_records;
CREATE POLICY synced_records_select ON public.synced_records FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY synced_records_insert ON public.synced_records FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY synced_records_update ON public.synced_records FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY synced_records_delete ON public.synced_records FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Server-controlled timestamps: clients cannot back-date or future-date rows.
CREATE OR REPLACE FUNCTION public.synced_records_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS synced_records_touch_trg ON public.synced_records;
CREATE TRIGGER synced_records_touch_trg
  BEFORE INSERT OR UPDATE ON public.synced_records
  FOR EACH ROW EXECUTE FUNCTION public.synced_records_touch();

-- Per-user, per-kind row cap so one account cannot fill the database.
-- History is pruned client-side; this is the hard server-side backstop.
CREATE OR REPLACE FUNCTION public.synced_records_quota()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  cap integer := CASE NEW.kind
    WHEN 'history'   THEN 20000
    WHEN 'search'    THEN 5000
    WHEN 'bookmark'  THEN 20000
    WHEN 'download'  THEN 5000
    ELSE 2000
  END;
  n integer;
BEGIN
  SELECT count(*) INTO n FROM public.synced_records
   WHERE user_id = NEW.user_id AND profile_id = NEW.profile_id AND kind = NEW.kind;
  IF n >= cap THEN
    RAISE EXCEPTION 'quota exceeded for kind %', NEW.kind USING ERRCODE = '54000';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS synced_records_quota_trg ON public.synced_records;
CREATE TRIGGER synced_records_quota_trg
  BEFORE INSERT ON public.synced_records
  FOR EACH ROW EXECUTE FUNCTION public.synced_records_quota();

-- ---------------------------------------------------------------------------
-- 4. Verification queries (run manually; both must return zero rows).
-- ---------------------------------------------------------------------------
-- Policies that still use a bare `true` expression:
--   SELECT tablename, policyname FROM pg_policies
--    WHERE schemaname = 'public' AND (qual = 'true' OR with_check = 'true');
-- Anon privileges on user data:
--   SELECT table_name, privilege_type FROM information_schema.role_table_grants
--    WHERE grantee = 'anon' AND table_schema = 'public';
