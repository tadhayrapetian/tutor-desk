-- TUTOR DESK v6 billing foundation.
-- Run after cloud/schema.sql. Never grant browser clients write access to subscriptions.

create table if not exists public.tutor_billing_events (
  id bigint generated always as identity primary key,
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  user_id uuid references auth.users(id) on delete set null,
  received_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  unique(provider, provider_event_id)
);
alter table public.tutor_billing_events enable row level security;
-- No policies by design: browser clients cannot read or write billing webhook events.

create or replace function public.tutor_my_entitlements()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_sub public.tutor_subscriptions%rowtype;
  v_pro boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select * into v_sub from public.tutor_subscriptions where user_id = auth.uid();
  if not found then
    return jsonb_build_object('plan','free','status','inactive','pro',false,
      'features',jsonb_build_object('local_workspace',true,'lesson_builder',true,'print_pdf',true,'cloud_sync',false,'cloud_files',false,'advanced_exports',false));
  end if;
  v_pro := v_sub.plan = 'pro'
    and v_sub.status in ('active','trialing')
    and (v_sub.period_end is null or v_sub.period_end > now());
  return jsonb_build_object(
    'plan', v_sub.plan,
    'status', v_sub.status,
    'period_end', v_sub.period_end,
    'pro', v_pro,
    'features', jsonb_build_object(
      'local_workspace', true,
      'lesson_builder', true,
      'print_pdf', true,
      'cloud_sync', true,
      'cloud_files', v_pro,
      'advanced_exports', v_pro,
      'multi_device_priority', v_pro
    )
  );
end;
$$;
revoke all on function public.tutor_my_entitlements() from public;
grant execute on function public.tutor_my_entitlements() to authenticated;

-- Only trusted server/service-role callers may apply normalized billing events.
create or replace function public.tutor_apply_billing_event(
  p_provider text,
  p_provider_event_id text,
  p_event_type text,
  p_user_id uuid,
  p_plan text,
  p_status text,
  p_period_end timestamptz default null,
  p_provider_customer_id text default null,
  p_provider_subscription_id text default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(auth.role(), '');
  v_inserted_id bigint;
begin
  if v_role <> 'service_role' then
    raise exception 'Forbidden: trusted billing server only';
  end if;
  if p_provider is null or length(trim(p_provider)) = 0
    or p_provider_event_id is null or length(trim(p_provider_event_id)) = 0 then
    raise exception 'Provider and event ID are required';
  end if;
  if p_plan not in ('free','trial','pro') then raise exception 'Invalid plan'; end if;
  if p_status not in ('active','trialing','past_due','canceled','inactive') then raise exception 'Invalid status'; end if;

  insert into public.tutor_billing_events(provider, provider_event_id, event_type, user_id, payload)
  values (p_provider, p_provider_event_id, p_event_type, p_user_id, coalesce(p_payload,'{}'::jsonb))
  on conflict (provider, provider_event_id) do nothing
  returning id into v_inserted_id;

  if v_inserted_id is null then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;

  insert into public.tutor_subscriptions(user_id, plan, status, period_end, provider, provider_customer_id, provider_subscription_id, updated_at)
  values (p_user_id, p_plan, p_status, p_period_end, p_provider, p_provider_customer_id, p_provider_subscription_id, now())
  on conflict (user_id) do update set
    plan = excluded.plan,
    status = excluded.status,
    period_end = excluded.period_end,
    provider = excluded.provider,
    provider_customer_id = coalesce(excluded.provider_customer_id, public.tutor_subscriptions.provider_customer_id),
    provider_subscription_id = coalesce(excluded.provider_subscription_id, public.tutor_subscriptions.provider_subscription_id),
    updated_at = now();

  return jsonb_build_object('ok', true, 'duplicate', false);
end;
$$;
revoke all on function public.tutor_apply_billing_event(text,text,text,uuid,text,text,timestamptz,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.tutor_apply_billing_event(text,text,text,uuid,text,text,timestamptz,text,text,jsonb) to service_role;
