-- Adds an optional doodle to a guestbook entry, uploaded to R2 first via
-- POST /api/guestbook/drawing, then referenced here by key.
alter table guestbook_entries add column if not exists image_key text;

-- Lets a user rename themselves from the dashboard without a full profile
-- table — one column is enough for what's editable today.
alter table users add column if not exists updated_at timestamptz not null default now();
