-- TUTOR DESK Web v5: run this in the Supabase SQL Editor.
-- Never put service_role/secret keys in browser code.

create table if not exists public.tutor_workspace_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  revision bigint not null default 1
);
alter table public.tutor_workspace_state add column if not exists revision bigint not null default 1;
alter table public.tutor_workspace_state enable row level security;
drop policy if exists "Users can read their own workspace" on public.tutor_workspace_state;
drop policy if exists "Users can insert their own workspace" on public.tutor_workspace_state;
drop policy if exists "Users can update their own workspace" on public.tutor_workspace_state;
create policy "Users can read their own workspace" on public.tutor_workspace_state for select to authenticated using (auth.uid() = user_id);
create policy "Users can insert their own workspace" on public.tutor_workspace_state for insert to authenticated with check (auth.uid() = user_id);
create policy "Users can update their own workspace" on public.tutor_workspace_state for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Private bucket for material files. The first folder is always the user's auth UUID.
insert into storage.buckets (id, name, public, file_size_limit)
values ('tutor-materials', 'tutor-materials', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = 52428800;
drop policy if exists "Tutor files select own folder" on storage.objects;
drop policy if exists "Tutor files insert own folder" on storage.objects;
drop policy if exists "Tutor files update own folder" on storage.objects;
drop policy if exists "Tutor files delete own folder" on storage.objects;
create policy "Tutor files select own folder" on storage.objects for select to authenticated using (bucket_id = 'tutor-materials' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Tutor files insert own folder" on storage.objects for insert to authenticated with check (bucket_id = 'tutor-materials' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Tutor files update own folder" on storage.objects for update to authenticated using (bucket_id = 'tutor-materials' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'tutor-materials' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Tutor files delete own folder" on storage.objects for delete to authenticated using (bucket_id = 'tutor-materials' and (storage.foldername(name))[1] = auth.uid()::text);

-- Subscription status is read-only from the browser. A trusted billing webhook/server
-- must manage status and plan fields; do not let users grant themselves Pro access.
create table if not exists public.tutor_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null default 'free' check (plan in ('free','trial','pro')),
  status text not null default 'inactive' check (status in ('active','trialing','past_due','canceled','inactive')),
  period_end timestamptz,
  provider text,
  provider_customer_id text,
  provider_subscription_id text,
  updated_at timestamptz not null default now()
);
alter table public.tutor_subscriptions enable row level security;
drop policy if exists "Users can read own subscription" on public.tutor_subscriptions;
create policy "Users can read own subscription" on public.tutor_subscriptions for select to authenticated using (auth.uid() = user_id);

create or replace function public.tutor_create_free_subscription()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  insert into public.tutor_subscriptions(user_id, plan, status)
  values (new.id, 'free', 'inactive')
  on conflict (user_id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created_tutor_subscription on auth.users;
create trigger on_auth_user_created_tutor_subscription after insert on auth.users
for each row execute procedure public.tutor_create_free_subscription();
insert into public.tutor_subscriptions(user_id, plan, status)
select id, 'free', 'inactive' from auth.users on conflict (user_id) do nothing;

-- Before a commercial launch: add a trusted billing provider + server/webhook to update
-- tutor_subscriptions. Do not create any client INSERT/UPDATE/DELETE policy on that table.
