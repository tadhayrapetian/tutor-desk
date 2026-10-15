# TUTOR DESK v7 — billing smoke test checklist

## Checkout
- [ ] Unauthenticated request returns 401.
- [ ] Unknown plan ID returns 400.
- [ ] Missing Paddle key/price ID returns 503 and creates no transaction.
- [ ] Browser cannot provide amount, currency, or price ID.
- [ ] Sandbox checkout returns an HTTPS Paddle URL.

## Webhook
- [ ] Missing signature returns 401.
- [ ] Signature computed against modified JSON whitespace returns 401.
- [ ] Expired timestamp returns 401.
- [ ] Valid signature with malformed JSON returns 400.
- [ ] Unknown event type returns 200 with ignored=true.
- [ ] Subscription event without trusted user reference returns 400.
- [ ] Duplicate event ID does not reapply subscription update.
- [ ] Browser cannot execute tutor_apply_billing_event.
- [ ] Pro access is granted only after a valid Paddle webhook updates server state.

## Lifecycle
- [ ] active -> Pro enabled.
- [ ] past_due -> Pro disabled according to current entitlement policy.
- [ ] canceled -> Pro disabled when Paddle cancellation takes effect.
- [ ] paused -> Pro disabled.
- [ ] period_end in the past -> Pro disabled even if status still says active.
