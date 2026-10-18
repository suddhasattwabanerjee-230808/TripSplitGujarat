# Google sign-in setup

The app (1.5.0+) signs in with Google only — no OTP. Getting it working
takes three parts: Google Cloud credentials, a backend update on `nav-server`,
and the Web client ID added to the app.

## 1. Google Cloud Console (one time, ~10 min)

Use the **same Cloud project that holds the Google Maps API key**.

1. **OAuth consent screen**: go to *APIs & Services → OAuth consent screen*
   (on newer consoles, *Google Auth Platform → Branding*).
   - User type: **External**. App name: `TripSplit`. Add your support and
     developer email.
   - Scopes: the defaults (`email`, `profile`, `openid`) are enough.
   - *Audience*: either click **Publish app** (anyone can sign in, and these
     scopes need no Google review) or stay in *Testing* and add each
     tripmate's Gmail under **Test users**.
2. **Web client** (the app and the server both use its ID):
   *Credentials → Create credentials → OAuth client ID → Web application*,
   name `TripSplit server`. Leave the redirect URIs empty. Copy the
   **Client ID** (`…apps.googleusercontent.com`).
3. **Android client, release build**: *Create credentials → OAuth client ID →
   Android*.
   - Package name: `com.example.trip_split_gujarat`
   - SHA-1: `CC:F1:7A:DD:B4:5D:EA:72:5C:20:49:FF:53:01:0A:4C:4E:19:C9:6F`
4. **Android client, debug build** (only needed for `flutter run`): the same
   package and SHA-1 `89:FF:0C:CF:FC:E8:3A:87:EF:31:5F:28:AC:B3:DA:B1:2F:6F:86:96`.

Without the Android client that matches the APK's signing SHA-1, sign-in
fails with a "misconfigured" error. Nothing is downloaded: there is no
`google-services.json` and no Firebase.

## 2. Backend (`tripsplit_backend` on nav-server)

1. `pip install google-auth requests` in the backend's venv.
2. Copy `google_auth.py` next to the backend's main module, then:
   ```python
   from google_auth import router as google_auth_router, migrate as google_auth_migrate
   google_auth_migrate()
   app.include_router(google_auth_router)
   ```
3. Fix the spots marked `ADAPT` to match the real DB code: the DB path, the
   session lookup and creation, and `users.phone` (it must allow NULL).
4. **Permanent login:** remove any session expiry from the existing auth check,
   so tokens stay valid until the user signs out. The app also renews a
   rejected session silently through Google, but phone-only accounts can't
   renew, so expiry has to go.
5. Set `GOOGLE_WEB_CLIENT_ID=<Web client ID from step 1.2>` in the service
   environment and restart.
6. Check that `curl https://nav-server.tail85596c.ts.net/openapi.json` lists
   `/auth/google` and `/me`.
7. Optional: remove `/auth/request-otp` and `/auth/verify-otp`. The app no
   longer calls them.

### API contract the app expects

| Endpoint | Body | Returns |
|---|---|---|
| `POST /auth/google` | `{"id_token": "<Google ID token>"}`. If an `Authorization: Bearer` session is sent too, Google is linked to that account. | `{"token": "...", "user": User}`. Bad Google token → 401. Google account already used elsewhere → 409. |
| `GET /me` | — | `User` |
| `PATCH /me` | `{"name": "..."}` | `User` |

`User` is `{"id", "name", "phone" (nullable), "email" (nullable), "photo_url" (nullable)}`.
A missing or invalid session must return **401**: that status triggers the
app's silent renewal.

## 3. App

Put the Web client ID in `lib/env.dart` → `googleWebClientId`, then release.

## Existing phone-login users

Their saved sessions keep working (once expiry is removed). The profile
screen shows **Connect Google**, which links Google to the same account so
all their trips stay put.
