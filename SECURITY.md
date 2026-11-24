# Security policy

Please report vulnerabilities privately through GitHub's "Report a vulnerability"
(Security tab) rather than a public issue. Include steps to reproduce and the
affected version. We aim to acknowledge reports within a few days.

The supabase anon key in `lib/utils/constants.dart` is the **public** client key
by design; all data access is restricted by Row Level Security
(`supabase/001_secure_sync.sql`). Never commit a `service_role` key.
