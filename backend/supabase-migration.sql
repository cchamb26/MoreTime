-- MoreTime Supabase Migration
-- Run this in the Supabase SQL Editor to create all required tables.

-- Clean slate: drop any existing tables and functions
drop table if exists public.chat_messages cascade;
drop table if exists public.file_uploads cascade;
drop table if exists public.schedule_blocks cascade;
drop table if exists public.tasks cascade;
drop table if exists public.courses cascade;
drop table if exists public.profiles cascade;
drop function if exists public.handle_new_user() cascade;

-- Profiles table (linked to Supabase Auth users)
create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  email text not null,
  name text not null,
  timezone text not null default 'America/New_York',
  preferences jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Auto-create profile when a new auth user is created
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, name, timezone)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'timezone', 'America/New_York')
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Courses
create table public.courses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  color text not null default '#6B7280',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_courses_user_id on public.courses(user_id);

-- Tasks
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid references public.courses(id) on delete set null,
  title text not null,
  description text not null default '',
  due_date timestamptz,
  priority integer not null default 2,
  estimated_hours double precision not null default 1.0,
  status text not null default 'pending',
  recurrence jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_tasks_user_id on public.tasks(user_id);
create index idx_tasks_course_id on public.tasks(course_id);
create index idx_tasks_due_date on public.tasks(due_date);

-- Schedule Blocks
create table public.schedule_blocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  date date not null,
  start_time text not null,
  end_time text not null,
  is_locked boolean not null default false,
  label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_schedule_blocks_user_date on public.schedule_blocks(user_id, date);
create index idx_schedule_blocks_task_id on public.schedule_blocks(task_id);

-- File Uploads
create table public.file_uploads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid references public.courses(id) on delete set null,
  original_name text not null,
  storage_path text not null,
  mime_type text not null,
  file_size integer not null,
  parsed_content text,
  parse_status text not null default 'pending',
  parsed_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_file_uploads_user_id on public.file_uploads(user_id);
create index idx_file_uploads_course_id on public.file_uploads(course_id);

-- Chat Messages
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null,
  content text not null,
  session_id text not null,
  timestamp timestamptz not null default now()
);
create index idx_chat_messages_user_session on public.chat_messages(user_id, session_id);
create index idx_chat_messages_timestamp on public.chat_messages(timestamp);

-- Enable RLS on all tables (service role key bypasses RLS, so this is a safety net)
alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.tasks enable row level security;
alter table public.schedule_blocks enable row level security;
alter table public.file_uploads enable row level security;
alter table public.chat_messages enable row level security;

-- RLS policies: allow users to access only their own data
create policy "Users can view own profile" on public.profiles for select using (auth.uid() = id);
create policy "Users can update own profile" on public.profiles for update using (auth.uid() = id);
create policy "Users can manage own courses" on public.courses for all using (auth.uid() = user_id);
create policy "Users can manage own tasks" on public.tasks for all using (auth.uid() = user_id);
create policy "Users can manage own schedule" on public.schedule_blocks for all using (auth.uid() = user_id);
create policy "Users can manage own files" on public.file_uploads for all using (auth.uid() = user_id);
create policy "Users can manage own chat" on public.chat_messages for all using (auth.uid() = user_id);
