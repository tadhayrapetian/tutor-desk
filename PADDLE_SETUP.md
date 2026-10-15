# TUTOR DESK v7 — подключение Paddle Billing

> Интеграция написана для Paddle Billing, но **не активирует реальные списания сама по себе**. Нужны одобренный аккаунт Paddle, созданный продукт, две recurring prices, одобренный домен Checkout и тестирование в sandbox.

## Перед началом

Paddle указывает Армению среди поддерживаемых стран для продаж, но Россия указана среди неподдерживаемых стран поставщиков и покупателей. До live-режима убедитесь, что юридическое лицо/статус продавца и география клиентов соответствуют актуальным правилам Paddle. Официальные источники:
- https://www.paddle.com/help/legal/sanctions/which-countries-are-supported-by-paddle
- https://developer.paddle.com/concepts/sell/supported-countries-locales/

## 1. Создать продукт и цены

В Paddle создайте продукт TUTOR DESK Pro и две повторяющиеся цены:
- месячная — скопируйте `pri_...` в `PADDLE_PRICE_ID_PRO_MONTHLY`;
- годовая — скопируйте `pri_...` в `PADDLE_PRICE_ID_PRO_YEARLY`.

Не задавайте цену из браузера: сервер выбирает только эти ID. Для начала используйте sandbox API key и sandbox prices.

## 2. Настроить Supabase

Выполните по порядку в SQL Editor:
1. `cloud/schema.sql`
2. `cloud/migrations/002_billing_entitlements.sql`
3. `cloud/migrations/003_paddle_billing.sql`

## 3. Секреты Edge Functions

Пример для Supabase CLI (замените значения своими):

```bash
supabase secrets set APP_ORIGIN=https://your-approved-app-domain.example
supabase secrets set PADDLE_ENVIRONMENT=sandbox
supabase secrets set PADDLE_API_KEY=pdl_sdbx_apikey_REPLACE_ME
supabase secrets set PADDLE_PRICE_ID_PRO_MONTHLY=pri_REPLACE_MONTHLY
supabase secrets set PADDLE_PRICE_ID_PRO_YEARLY=pri_REPLACE_YEARLY
supabase secrets set PADDLE_CHECKOUT_URL=https://your-approved-app-domain.example
```

`PADDLE_CHECKOUT_URL` должен быть доменом, одобренным в настройках Paddle. Для Edge Functions также доступны штатные `SUPABASE_URL`, `SUPABASE_ANON_KEY` и `SUPABASE_SERVICE_ROLE_KEY`.

## 4. Развернуть функции

```bash
supabase functions deploy create-checkout-session
supabase functions deploy billing-webhook --no-verify-jwt
```

В Paddle Developer Tools создайте Notification Destination для URL:

`https://YOUR_PROJECT_REF.supabase.co/functions/v1/billing-webhook`

Выберите события подписки: `subscription.created`, `subscription.activated`, `subscription.updated`, `subscription.canceled`, `subscription.past_due`, `subscription.paused`. Сохраните выданный destination secret и задайте его в Supabase:

```bash
supabase secrets set PADDLE_WEBHOOK_SECRET=pdl_ntfset_REPLACE_ME
```

Webhook проверяет родную подпись Paddle `Paddle-Signature` на точном исходном теле запроса, с HMAC-SHA256 и временным окном 5 минут. События дедуплицируются SQL-функцией по `provider + event_id`.

## 5. Обязательные sandbox-тесты

- checkout месячного плана и годового плана;
- успешная оплата, отмена checkout и отказ оплаты;
- `subscription.created`, обновление, отмена, past_due и повторная доставка одного события;
- неправильная подпись, устаревшая подпись и неизвестный price ID;
- убедиться, что browser client не может изменить `tutor_subscriptions`;
- проверить, что статус Pro меняется только после подписанного webhook, а не по возврату браузера.

## Ограничения этой версии

- Нужны реальные Paddle price IDs и ключи, аккаунт не подключён из этого архива.
- Автоматическая обработка возвратов, chargebacks, изменение способа оплаты и пользовательский портал управления подпиской не реализованы.
- Если Paddle не переносит `custom_data.tutor_user_id` в событие подписки для выбранного сценария, webhook намеренно отклонит событие; проверьте payload на sandbox и скорректируйте надёжную серверную привязку, не доверяя URL-параметрам браузера.
- Перед коммерческим запуском нужны аудит RLS, тесты в развёрнутом Supabase, юридические документы и политика удаления данных.
