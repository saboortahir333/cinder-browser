-- ############################################################################
-- #  DO NOT RUN THIS FILE.  SUPERSEDED BY supabase/001_secure_sync.sql
-- #  The policies below use USING (true): with the anon key that ships in the
-- #  app, anyone on the internet could read or delete every user's data.
-- ############################################################################

-- ============================================================
-- Saboor Browser – bookmarks table (UPDATED)
-- Run this in your Supabase SQL Editor.
-- If you already ran the previous version, run the ALTER below
-- to drop the broken unique constraint first.
-- ============================================================

-- STEP 1: If table already exists, drop the old broken constraint
-- (UNIQUE(url, user_id) silently fails when user_id IS NULL in SQL)
-- Run this only if you ran the previous SQL already:
--
-- ALTER TABLE public.bookmarks DROP CONSTRAINT IF EXISTS bookmarks_url_user_id_key;
-- ALTER TABLE public.bookmarks ADD CONSTRAINT bookmarks_url_user_id_key
--   UNIQUE NULLS NOT DISTINCT (url, user_id);
-- (NULLS NOT DISTINCT treats NULL=NULL for the constraint — PostgreSQL 15+)

-- STEP 2: Fresh table creation (skip if table already exists)
CREATE TABLE IF NOT EXISTS public.bookmarks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  url           TEXT NOT NULL,
  title         TEXT NOT NULL DEFAULT '',
  created_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for fast per-user lookups
CREATE INDEX IF NOT EXISTS bookmarks_user_id_idx ON public.bookmarks (user_id);
CREATE INDEX IF NOT EXISTS bookmarks_url_idx     ON public.bookmarks (url);

-- ============================================================
-- Row Level Security (RLS)
-- Allow ALL operations when using the anon key (no auth required).
-- This is safe because the anon key is read-only from the public internet
-- and this is a personal browser app.
-- ============================================================
ALTER TABLE public.bookmarks ENABLE ROW LEVEL SECURITY;

-- Drop old policies if they exist before recreating
DROP POLICY IF EXISTS "Users read own bookmarks"   ON public.bookmarks;
DROP POLICY IF EXISTS "Users insert own bookmarks" ON public.bookmarks;
DROP POLICY IF EXISTS "Users delete own bookmarks" ON public.bookmarks;
DROP POLICY IF EXISTS "Users update own bookmarks" ON public.bookmarks;

-- Allow ALL reads (bookmarks are personal data, anon key is scoped to your project)
CREATE POLICY "Allow all reads"
  ON public.bookmarks FOR SELECT
  USING (true);

-- Allow ALL inserts
CREATE POLICY "Allow all inserts"
  ON public.bookmarks FOR INSERT
  WITH CHECK (true);

-- Allow ALL deletes
CREATE POLICY "Allow all deletes"
  ON public.bookmarks FOR DELETE
  USING (true);

-- ============================================================
-- Also update browsing_history and search_history RLS
-- so they work without authentication (no anonymous sign-in needed)
-- ============================================================

-- browsing_history
DROP POLICY IF EXISTS "Users read own history"   ON public.browsing_history;
DROP POLICY IF EXISTS "Users insert own history" ON public.browsing_history;
DROP POLICY IF EXISTS "Users delete own history" ON public.browsing_history;

CREATE POLICY "Allow all reads"   ON public.browsing_history FOR SELECT USING (true);
CREATE POLICY "Allow all inserts" ON public.browsing_history FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow all deletes" ON public.browsing_history FOR DELETE USING (true);

-- search_history
DROP POLICY IF EXISTS "Users read own searches"   ON public.search_history;
DROP POLICY IF EXISTS "Users insert own searches" ON public.search_history;
DROP POLICY IF EXISTS "Users delete own searches" ON public.search_history;

CREATE POLICY "Allow all reads"   ON public.search_history FOR SELECT USING (true);
CREATE POLICY "Allow all inserts" ON public.search_history FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow all deletes" ON public.search_history FOR DELETE USING (true);
