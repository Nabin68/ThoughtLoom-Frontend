-- ThoughtLoom schema
--
-- Apply by pasting into the Supabase SQL editor, or:
--   supabase db push
--
-- Safe to re-run: every object is created idempotently.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.chat_category as enum ('education', 'financial', 'relationship', 'other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.chat_status as enum ('in_progress', 'completed');
exception when duplicate_object then null; end $$;

-- 'intake'            fixed per-category MCQ answered during the scripted opening
-- 'adaptive_question' follow-up the model wrote in response to this user
-- 'free_text'         anything the user typed or dictated of their own accord
-- 'recommendation'    the model's actual advice
do $$ begin
  create type public.message_type as enum (
    'intake', 'adaptive_question', 'free_text', 'recommendation'
  );
exception when duplicate_object then null; end $$;

-- Added after the enums above already existed in live projects, so these are
-- ALTERs rather than edits to the create statements — a create only runs on a
-- fresh database, and re-running this file must upgrade an old one too.
--
-- 'awaiting_follow_up': the recommendation has landed but the user can still
-- push back, and usually should. A chat is only 'completed' when they leave it,
-- which the client sets directly.
alter type public.chat_status add value if not exists 'awaiting_follow_up';

-- 'assistant_reply': the model's turns in the conversation *after* the
-- recommendation. Distinct from 'recommendation' so that "the advice" stays
-- findable in a chat that ran on for another twenty turns — Prompt 6's memory
-- summarisation will want exactly that one row.
alter type public.message_type add value if not exists 'assistant_reply';

-- ---------------------------------------------------------------------------
-- updated_at helper
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- user_profiles
--
-- Keyed by auth.users.id rather than carrying its own id, so the profile and
-- the account cannot drift apart and a deleted account takes its profile with
-- it. Onboarding answers live in jsonb because their shape is still being
-- designed; the columns promoted out of it are the ones every later query
-- filters or personalises on.
-- ---------------------------------------------------------------------------

create table if not exists public.user_profiles (
  id                   uuid primary key references auth.users (id) on delete cascade,
  display_name         text,
  age_range            text,
  occupation           text,
  location             text,
  onboarding_answers   jsonb       not null default '{}'::jsonb,
  onboarding_completed boolean     not null default false,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

drop trigger if exists user_profiles_touch_updated_at on public.user_profiles;
create trigger user_profiles_touch_updated_at
  before update on public.user_profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- chats
-- ---------------------------------------------------------------------------

create table if not exists public.chats (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  category   public.chat_category not null,
  title      text,
  status     public.chat_status   not null default 'in_progress',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- When this chat was folded into the user's long-term memory.
--
-- Added by Prompt 6 as an ALTER rather than a column above, for the same reason
-- the enum values are ALTERs: the create only fires on a fresh database, and
-- re-running this file has to upgrade an existing one too.
--
-- It exists to make the merge idempotent. Completing a chat can be requested
-- more than once — the client retries, and the history screen backfills a chat
-- whose titling never landed — and an AI merge run twice over the same
-- conversation would fold the same facts in twice.
alter table public.chats
  add column if not exists memory_merged_at timestamptz;

-- The chat list is always "mine, newest first".
create index if not exists chats_user_id_updated_at_idx
  on public.chats (user_id, updated_at desc);

-- Speeds up the chat search. pg_trgm makes a leading-wildcard ILIKE indexable,
-- which a b-tree cannot help with at all.
--
-- Non-fatal by design: pg_trgm lives in different schemas across Supabase
-- project vintages, and search is a nicety next to the tables actually being
-- created. Without the index the search still returns the right rows, just via
-- a scan — fine at one user's worth of chats.
do $$ begin
  create extension if not exists pg_trgm;
  create index if not exists chats_title_trgm_idx
    on public.chats using gin (title gin_trgm_ops);
exception when others then
  raise notice 'pg_trgm unavailable (%): chat title search will fall back to a scan.', sqlerrm;
end $$;

-- Scoped to the columns that mean "something happened in this conversation",
-- rather than firing on any update at all.
--
-- updated_at is what orders history and what the recall lookup treats as "most
-- recent", so it has to mean activity. Two of Prompt 6's writes are not
-- activity: the auto-titler writes `title`, and the memory merge writes
-- `memory_merged_at`, both of them minutes-to-months after the user stopped
-- talking. Left unscoped, backfilling the title of a chat from March would move
-- it to the top of the list, date it "Just now", and make it the first thing a
-- new chat was told it connected to.
--
-- `updated_at` is itself in the list because that is how a new message says a
-- chat is alive: the client and the service both write it explicitly, and this
-- trigger replaces the value they sent with the server's own clock.
drop trigger if exists chats_touch_updated_at on public.chats;
create trigger chats_touch_updated_at
  before update of status, category, updated_at on public.chats
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- messages
--
-- No user_id column: ownership is derived through chat_id. One source of truth
-- means a message can never end up attributed to someone who does not own its
-- chat.
-- ---------------------------------------------------------------------------

create table if not exists public.messages (
  id            uuid primary key default gen_random_uuid(),
  chat_id       uuid not null references public.chats (id) on delete cascade,
  seq           integer not null,
  type          public.message_type not null,
  question_text text,
  answer_text   text,
  -- Carries whatever a given turn needs without a migration: MCQ option lists,
  -- web-search citations behind a recommendation, model name, token counts.
  metadata      jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),

  constraint messages_chat_id_seq_key unique (chat_id, seq)
);

create index if not exists messages_chat_id_seq_idx
  on public.messages (chat_id, seq);

-- "The recommendation in chat X", which the recall lookup asks for a handful of
-- past chats at a time.
create index if not exists messages_chat_id_type_idx
  on public.messages (chat_id, type);

-- Chat search matches what was said as well as the title, and does it with a
-- leading-wildcard ILIKE — which no b-tree can help with. Same non-fatal
-- treatment as the title index above: without pg_trgm the search still returns
-- the right rows, just by scanning.
--
-- answer_text only. question_text is *our* words, not the conversation's: the
-- scripted intake questions are identical for everyone in a category, so
-- indexing them would mean searching "money" returned every financial chat ever
-- started on the strength of a question we asked. See SupabaseDataService.
do $$ begin
  create extension if not exists pg_trgm;
  create index if not exists messages_answer_text_trgm_idx
    on public.messages using gin (answer_text gin_trgm_ops);
exception when others then
  raise notice 'pg_trgm unavailable (%): message search will fall back to a scan.', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- user_memory
--
-- One row per (user, category), plus one row per user with category IS NULL
-- holding facts that hold true regardless of topic. Splitting by category
-- keeps a financial chat from being told about someone's relationships, while
-- the null row still carries "has two kids, based in Pune" everywhere.
--
-- Postgres treats NULLs as distinct in a UNIQUE constraint, so a plain
-- unique (user_id, category) would let unlimited global rows through. Two
-- partial indexes give real uniqueness on both sides of the split.
-- ---------------------------------------------------------------------------

create table if not exists public.user_memory (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  category   public.chat_category,
  summary    text  not null default '',
  facts      jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists user_memory_user_global_key
  on public.user_memory (user_id) where category is null;

create unique index if not exists user_memory_user_category_key
  on public.user_memory (user_id, category) where category is not null;

drop trigger if exists user_memory_touch_updated_at on public.user_memory;
create trigger user_memory_touch_updated_at
  before update on public.user_memory
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Provision a profile + global memory row the moment an account is created
--
-- Runs inside the signup transaction, so the app can read a profile straight
-- after sign-up without racing the client. security definer is required: the
-- trigger fires before the new user has a session to authorise the insert.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_profiles (id, display_name)
  values (new.id, nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''))
  on conflict (id) do nothing;

  insert into public.user_memory (user_id, category)
  values (new.id, null)
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- The app holds only the anon key and talks to Postgres directly, so these
-- policies are the entire authorisation model. Without them every table is
-- world-readable.
-- ---------------------------------------------------------------------------

alter table public.user_profiles enable row level security;
alter table public.chats         enable row level security;
alter table public.messages      enable row level security;
alter table public.user_memory   enable row level security;

drop policy if exists "own profile" on public.user_profiles;
create policy "own profile" on public.user_profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "own chats" on public.chats;
create policy "own chats" on public.chats
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Reached through the parent chat, so a message is visible exactly when its
-- chat is. with check uses the same test, which stops a client writing a
-- message into someone else's chat.
drop policy if exists "own messages" on public.messages;
create policy "own messages" on public.messages
  for all
  using (
    exists (
      select 1 from public.chats c
      where c.id = messages.chat_id and c.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.chats c
      where c.id = messages.chat_id and c.user_id = auth.uid()
    )
  );

drop policy if exists "own memory" on public.user_memory;
create policy "own memory" on public.user_memory
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
