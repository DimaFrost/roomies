-- Roomies initial schema: households, members, expenses, asks.
-- All objects are prefixed roomies_ because they live in a Supabase project
-- shared with another app.
-- Access model: every row belongs to a household; RLS grants access only to
-- authenticated users with a membership row in that household.

create table public.roomies_households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  invite_code text not null unique,
  created_at timestamptz not null default now()
);

create table public.roomies_members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.roomies_households on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  created_at timestamptz not null default now(),
  unique (household_id, user_id),
  unique (household_id, name)
);

create table public.roomies_expenses (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.roomies_households on delete cascade,
  description text not null check (char_length(description) between 1 and 200),
  amount numeric(10,2) not null check (amount > 0),
  category text not null,
  paid_by text not null,
  split text not null check (split in ('even', 'full')),
  for_person text,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.roomies_asks (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.roomies_households on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  note text,
  asked_by text not null,
  assigned_to text,
  status text not null default 'open' check (status in ('open', 'accepted', 'done')),
  accepted_by text,
  completed_at timestamptz,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create index roomies_expenses_household_created_idx on public.roomies_expenses (household_id, created_at desc);
create index roomies_asks_household_created_idx on public.roomies_asks (household_id, created_at desc);
create index roomies_members_user_idx on public.roomies_members (user_id);

-- Membership check used by all policies. SECURITY DEFINER so it can read
-- members regardless of the caller's own row visibility.
create or replace function public.roomies_is_member(h uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from roomies_members where household_id = h and user_id = (select auth.uid())
  );
$$;

alter table public.roomies_households enable row level security;
alter table public.roomies_members enable row level security;
alter table public.roomies_expenses enable row level security;
alter table public.roomies_asks enable row level security;

create policy "members can read their household"
  on public.roomies_households for select to authenticated
  using (public.roomies_is_member(id));

create policy "members can read household members"
  on public.roomies_members for select to authenticated
  using (public.roomies_is_member(household_id));

create policy "members full access to expenses"
  on public.roomies_expenses for all to authenticated
  using (public.roomies_is_member(household_id))
  with check (public.roomies_is_member(household_id));

create policy "members full access to asks"
  on public.roomies_asks for all to authenticated
  using (public.roomies_is_member(household_id))
  with check (public.roomies_is_member(household_id));

-- Households and memberships are created only through these RPCs, so invite
-- codes are validated server-side and nobody can insert themselves into an
-- arbitrary household.

create or replace function public.roomies_create_household(flat_name text, member_name text)
returns json
language plpgsql security definer
set search_path = public
as $$
declare
  h roomies_households;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  insert into roomies_households (name, invite_code)
  values (
    trim(flat_name),
    -- 6 chars from an unambiguous alphabet (no 0/O/1/I)
    (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (random() * 31)::int + 1, 1), '')
     from generate_series(1, 6))
  )
  returning * into h;
  insert into roomies_members (household_id, user_id, name) values (h.id, auth.uid(), trim(member_name));
  return json_build_object('id', h.id, 'name', h.name, 'invite_code', h.invite_code);
end;
$$;

create or replace function public.roomies_join_household(code text, member_name text)
returns json
language plpgsql security definer
set search_path = public
as $$
declare
  h roomies_households;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  select * into h from roomies_households where invite_code = upper(trim(code));
  if h.id is null then
    raise exception 'invalid invite code';
  end if;
  insert into roomies_members (household_id, user_id, name)
  values (h.id, auth.uid(), trim(member_name))
  on conflict (household_id, user_id) do update set name = excluded.name;
  return json_build_object('id', h.id, 'name', h.name, 'invite_code', h.invite_code);
end;
$$;

revoke execute on function public.roomies_create_household from anon;
revoke execute on function public.roomies_join_household from anon;
revoke execute on function public.roomies_is_member from anon;

-- Realtime change feeds for synced tables.
alter publication supabase_realtime add table public.roomies_expenses;
alter publication supabase_realtime add table public.roomies_asks;
alter publication supabase_realtime add table public.roomies_members;
