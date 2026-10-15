# Billing adapter contract (TUTOR DESK v6)

The payment provider is intentionally not selected in this scaffold. The adapter must:

1. Authenticate checkout requests from `create-checkout-session` using `BILLING_ADAPTER_SECRET`.
2. Accept only `plan_id=pro_monthly` or `pro_yearly`; map those IDs to prices stored on the server. Never trust a price or currency from the browser.
3. Create the provider checkout session and return `{ "url": "https://..." }`.
4. Verify the provider's original webhook signature with the provider's documented algorithm.
5. Map a verified event to this canonical event body:

```json
{
  "provider": "provider-name",
  "event_id": "unique-provider-event-id",
  "event_type": "subscription.activated",
  "user_id": "Supabase-auth-user-uuid",
  "plan": "pro",
  "status": "active",
  "period_end": "2026-11-16T00:00:00Z",
  "customer_id": "provider-customer-id",
  "subscription_id": "provider-subscription-id",
  "payload": { "redacted": true }
}
```

Allowed plans: `free`, `trial`, `pro`. Allowed statuses: `active`, `trialing`, `past_due`, `canceled`, `inactive`. `period_end` can be `null` for no fixed end. Use the actual Supabase user UUID stored as the provider's trusted customer reference at checkout; do not trust a user ID supplied by a customer in a browser redirect.

6. POST the exact JSON bytes to the `billing-webhook` Edge Function with `x-tutor-signature: sha256=<lowercase-hex-HMAC-SHA256>`, computed using `TUTOR_BILLING_WEBHOOK_SECRET`.
7. Handle duplicate webhook delivery safely; the SQL function deduplicates by provider and event ID.

Do not include payment card data, passwords, access tokens, or unnecessary personal data in `payload`.
