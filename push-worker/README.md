# TripSplit push relay

A [Cloudflare Worker](https://workers.cloudflare.com/) (free plan, no card) that
sends tripmates an instant phone notification when someone adds an expense,
even with TripSplit closed and the phone locked.

Firebase Cloud Messaging can only be sent with a service-account key, which must
never be inside the APK, and Cloud Functions need the paid Blaze plan. So the
payer's app calls this Worker with `{tripId, expenseId}` and its Firebase ID
token; the Worker checks the token and that the caller just added that expense,
then sends every other member a high-priority data push (FCM v1). Their app
draws the notification (photo, amount, details) in `lib/expense_notifier.dart`.

## Deploy

1. Firebase console → Project settings → **Service accounts** → **Generate new
   private key**. Keep the JSON file private; it never goes in this repo.
2. dash.cloudflare.com → **Workers & Pages** → **Create** → **Create Worker** →
   name it `tripsplit-push` → **Deploy** → **Edit code** → replace everything
   with `worker.js` → **Deploy**.
3. The Worker → **Settings** → **Variables and Secrets** → **Add** → type
   **Secret**, name `SERVICE_ACCOUNT`, value: the whole JSON file → **Deploy**.
4. Put the Worker's URL (`https://tripsplit-push.<you>.workers.dev`) in
   `pushRelayUrl` in `lib/env.dart`.

Opening the URL in a browser shows `TripSplit push relay`.

## Test

    node push-worker/test.mjs
