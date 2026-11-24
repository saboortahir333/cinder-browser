-- ############################################################################
-- #  DO NOT RUN THIS FILE.  SUPERSEDED BY supabase/001_secure_sync.sql
-- #  The policies below use USING (true): with the anon key that ships in the
-- #  app, anyone on the internet could read or delete every user's data.
-- ############################################################################

-- Run this in your Supabase SQL Editor to create the user_settings table

CREATE TABLE IF NOT EXISTS public.user_settings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE, -- Optional: Links to Supabase Auth if logged in
    setting_key TEXT NOT NULL,
    setting_value TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Ensure setting_key is unique per user (or globally unique for unauthenticated users)
-- This is necessary for the .upsert() method to work properly.
CREATE UNIQUE INDEX IF NOT EXISTS user_settings_key_user_idx ON public.user_settings (setting_key, (COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid)));

-- Row Level Security (Optional but recommended)
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- Allow anonymous access (if your app allows saving settings without login)
CREATE POLICY "Allow public read/write to settings" 
ON public.user_settings 
FOR ALL 
USING (true) 
WITH CHECK (true);
