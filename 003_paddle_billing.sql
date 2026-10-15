-- TUTOR DESK v7: Paddle Billing audit fields and least-privilege defaults.
-- Run after cloud/schema.sql and cloud/migrations/002_billing_entitlements.sql.

create index if not exists tutor_billing_events_user_received_idx
  on public.tutor_billing_events (user_id, received_at desc);
create index if not exists tutor_subscriptions_provider_subscription_idx
  on public.tutor_subscriptions (provider, provider_subscription_id)
  where provider_subscription_id is not null;

-- Explicitly preserve the rule: browser users may read their own subscription,
-- but only the trusted webhook/service role may update it.
alter table public.tutor_subscriptions enable row level security;
drop policy if exists "Users can insert own subscription" on public.tutor_subscriptions;
drop policy if exists "Users can update own subscription" on public.tutor_subscriptions;
drop policy if exists "Users can delete own subscription" on public.tutor_subscriptions;

-- Do not add policies to tutor_billing_events; it intentionally has no client-facing policies.
