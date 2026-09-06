-- Neon Postgres schema for salesforce.imswarnil.com.
-- Apply with: psql "$DATABASE_URL" -f db/migrations/0001_init.sql
-- (or via `npm run db:migrate`, see scripts/migrate.mjs)

create extension if not exists pgcrypto;

create table if not exists users (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique,
  password_hash text not null,
  display_name  text not null,
  created_at    timestamptz not null default now()
);

create table if not exists sessions (
  id         text primary key, -- random token, hashed before storage — see server/utils/auth.ts
  user_id    uuid not null references users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists sessions_user_id_idx on sessions(user_id);

-- One row per lesson a learner has marked complete. lesson_slug matches the
-- Nuxt Content path, e.g. "data-model/data-modeling".
create table if not exists lesson_progress (
  user_id      uuid not null references users(id) on delete cascade,
  lesson_slug  text not null,
  completed_at timestamptz not null default now(),
  primary key (user_id, lesson_slug)
);

create table if not exists comments (
  id          uuid primary key default gen_random_uuid(),
  lesson_slug text not null,
  user_id     uuid not null references users(id) on delete cascade,
  body        text not null,
  hidden      boolean not null default false, -- soft-moderation flag
  created_at  timestamptz not null default now()
);
create index if not exists comments_lesson_slug_idx on comments(lesson_slug, created_at);

create table if not exists guestbook_entries (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references users(id) on delete set null,
  display_name text not null,
  message      text not null,
  hidden       boolean not null default false,
  created_at   timestamptz not null default now()
);

create table if not exists resource_submissions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,
  title       text not null,
  url         text,
  r2_key      text, -- set when an attachment was uploaded instead of/alongside a url
  description text not null,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at  timestamptz not null default now()
);

create table if not exists suggestions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references users(id) on delete set null,
  category   text not null check (category in ('lesson-idea', 'bug', 'demo-org', 'other')),
  body       text not null,
  status     text not null default 'open' check (status in ('open', 'planned', 'done', 'declined')),
  created_at timestamptz not null default now()
);
