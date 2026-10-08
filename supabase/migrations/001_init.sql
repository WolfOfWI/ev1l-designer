-- Ev1l Designer: initial database setup
-- Run once in Supabase: Dashboard -> SQL Editor -> New query -> paste this file -> Run.
--
-- Model: every user gets a private WORKSPACE on sign-up. All data belongs to a workspace, and
-- row-level security (RLS) only lets workspace members see or change it. Adding teammates later
-- is just a row in workspace_members, so no rebuild is needed to support teams or other companies.

-- ───────────────────────── Workspaces & members ─────────────────────────
create table if not exists public.workspaces (
  id          uuid primary key default gen_random_uuid(),
  name        text not null default 'My workspace',
  owner_id    uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         text not null default 'member' check (role in ('owner','admin','member','viewer')),
  created_at   timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text,
  default_workspace uuid references public.workspaces(id) on delete set null,
  created_at    timestamptz not null default now()
);

-- Membership checks used by every policy (security definer avoids recursive RLS lookups)
create or replace function public.is_member(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from workspace_members m where m.workspace_id = ws and m.user_id = auth.uid());
$$;
create or replace function public.is_admin(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from workspace_members m where m.workspace_id = ws and m.user_id = auth.uid() and m.role in ('owner','admin'));
$$;
create or replace function public.can_edit(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from workspace_members m where m.workspace_id = ws and m.user_id = auth.uid() and m.role <> 'viewer');
$$;

-- New user -> profile + personal workspace + owner membership
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare ws uuid;
begin
  insert into workspaces (name, owner_id) values (coalesce(split_part(new.email,'@',1),'My') || '''s workspace', new.id) returning id into ws;
  insert into workspace_members (workspace_id, user_id, role) values (ws, new.id, 'owner');
  insert into profiles (id, display_name, default_workspace) values (new.id, split_part(new.email,'@',1), ws);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- ───────────────────────── App data ─────────────────────────
-- Redline plans: markup, calibration and per-sheet data live in `data` (JSON);
-- the PDF itself lives in Storage at plans/<workspace_id>/<plan_id>.pdf
create table if not exists public.plans (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references public.workspaces(id) on delete cascade,
  name          text not null default 'Untitled plan',
  job           text,
  pdf_path      text,
  data          jsonb not null default '{}'::jsonb,
  version       integer not null default 1,      -- bumped on every save (simple conflict detection)
  deleted       boolean not null default false,  -- soft delete (recoverable)
  created_by    uuid references auth.users(id),
  updated_by    uuid references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists plans_ws_idx on public.plans (workspace_id, updated_at desc);

-- Sq Ft Estimator sessions (areas, notes, scale, overlay alignment); plan image + overlay image in Storage
create table if not exists public.estimator_sessions (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references public.workspaces(id) on delete cascade,
  name          text not null,
  plan_id       uuid references public.plans(id) on delete set null,
  data          jsonb not null default '{}'::jsonb,
  bg_path       text,
  overlay_path  text,
  version       integer not null default 1,
  deleted       boolean not null default false,
  updated_by    uuid references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists sessions_ws_idx on public.estimator_sessions (workspace_id, updated_at desc);

-- "My Symbols" library (true-size reusable symbols)
create table if not exists public.symbols (
  id            uuid primary key default gen_random_uuid(),
  workspace_id  uuid not null references public.workspaces(id) on delete cascade,
  name          text not null,
  def           jsonb not null,
  created_at    timestamptz not null default now()
);

-- Workspace settings: company & brand names, units, plan database, etc.
create table if not exists public.workspace_settings (
  workspace_id  uuid primary key references public.workspaces(id) on delete cascade,
  settings      jsonb not null default '{}'::jsonb,
  updated_at    timestamptz not null default now()
);

-- Keep updated_at / version current automatically
create or replace function public.touch() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' and to_jsonb(new) ? 'version' then new.version := old.version + 1; end if;
  return new;
end $$;
drop trigger if exists plans_touch on public.plans;
create trigger plans_touch before update on public.plans for each row execute function public.touch();
drop trigger if exists sessions_touch on public.estimator_sessions;
create trigger sessions_touch before update on public.estimator_sessions for each row execute function public.touch();
drop trigger if exists settings_touch on public.workspace_settings;
create trigger settings_touch before update on public.workspace_settings for each row execute function public.touch();

-- ───────────────────────── Row-level security ─────────────────────────
alter table public.workspaces         enable row level security;
alter table public.workspace_members  enable row level security;
alter table public.profiles           enable row level security;
alter table public.plans              enable row level security;
alter table public.estimator_sessions enable row level security;
alter table public.symbols            enable row level security;
alter table public.workspace_settings enable row level security;

drop policy if exists ws_read on public.workspaces;
create policy ws_read on public.workspaces for select using (public.is_member(id));
drop policy if exists ws_rename on public.workspaces;
create policy ws_rename on public.workspaces for update using (owner_id = auth.uid());

drop policy if exists wm_read on public.workspace_members;
create policy wm_read on public.workspace_members for select using (public.is_member(workspace_id));
drop policy if exists wm_manage on public.workspace_members;
-- (uses a security-definer function: a policy that queries its own table recurses forever)
create policy wm_manage on public.workspace_members for all
  using (public.is_admin(workspace_id)) with check (public.is_admin(workspace_id));

drop policy if exists profile_self on public.profiles;
create policy profile_self on public.profiles for all using (id = auth.uid()) with check (id = auth.uid());

-- Same rule for every data table: members read, non-viewers write
do $$
declare t text;
begin
  foreach t in array array['plans','estimator_sessions','symbols','workspace_settings'] loop
    execute format('drop policy if exists %1$s_read on public.%1$s', t);
    execute format('create policy %1$s_read on public.%1$s for select using (public.is_member(workspace_id))', t);
    execute format('drop policy if exists %1$s_insert on public.%1$s', t);
    execute format('create policy %1$s_insert on public.%1$s for insert with check (public.can_edit(workspace_id))', t);
    execute format('drop policy if exists %1$s_update on public.%1$s', t);
    execute format('create policy %1$s_update on public.%1$s for update using (public.can_edit(workspace_id)) with check (public.can_edit(workspace_id))', t);
    execute format('drop policy if exists %1$s_delete on public.%1$s', t);
    execute format('create policy %1$s_delete on public.%1$s for delete using (public.can_edit(workspace_id))', t);
  end loop;
end $$;

-- ───────────────────────── File storage ─────────────────────────
-- One private bucket; files are stored under <workspace_id>/..., and access follows membership.
insert into storage.buckets (id, name, public, file_size_limit)
values ('plans', 'plans', false, 52428800)   -- 50 MB per file (raise on the Pro plan if needed)
on conflict (id) do nothing;

drop policy if exists plans_files_read on storage.objects;
create policy plans_files_read on storage.objects for select
  using (bucket_id = 'plans' and public.is_member(((storage.foldername(name))[1])::uuid));
drop policy if exists plans_files_write on storage.objects;
create policy plans_files_write on storage.objects for insert
  with check (bucket_id = 'plans' and public.can_edit(((storage.foldername(name))[1])::uuid));
drop policy if exists plans_files_update on storage.objects;
create policy plans_files_update on storage.objects for update
  using (bucket_id = 'plans' and public.can_edit(((storage.foldername(name))[1])::uuid));
drop policy if exists plans_files_delete on storage.objects;
create policy plans_files_delete on storage.objects for delete
  using (bucket_id = 'plans' and public.can_edit(((storage.foldername(name))[1])::uuid));
