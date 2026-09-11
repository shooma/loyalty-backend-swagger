# Polonez & Eastore Loyalty — Mobile App API onboarding

Practical guide for the mobile developer integrating against the **Mobile API**
on the staging server. The machine-readable contract is the Swagger:

- **Swagger UI:** https://shooma.github.io/loyalty-backend-swagger/ (`mobile.yaml`)
- This document is the human-friendly companion: environment, auth flow, how to
  get an OTP on staging without a real SMS, and ready-to-use demo accounts.

> The Mobile API (`/api/v1/mobile/...`) is a different surface from the POS /
> cash-register API (`/api/v1/loyalty/...`, see `loyalty.yaml`). As a mobile dev
> you only need the Mobile API.

---

## 1. Environment

| | |
|---|---|
| **Staging base URL** | `https://stage.odoo-stage.polonez.dev` |
| **Recommended prefix** | `/api/v1/mobile/...` (canonical) |
| **Fallback prefix** | `/odoo/api/v1/mobile/...` (temporary compatibility) |
| **Content type** | `application/json` |
| **DB selection** | host-based (`dbfilter`), nothing to send — just use the staging host |

> **Use the canonical `/api/v1/mobile/...` prefix** — it's the portable one across
> environments. The `/odoo/api/v1/mobile/...` prefix is a **temporary fallback**;
> both currently respond on staging. In the Swagger UI, pick the plain server entry
> (the one *without* `/odoo`). All paths and examples in this document use the
> canonical prefix.

All monetary amounts are **integers in minor units (cents)**: `300` = €3.00.

---

## 2. Authentication flow (phone + OTP)

Login is passwordless: request an OTP for a phone number, verify it, get a Bearer
session token. New phones go through a short signup step.

```
POST /api/v1/mobile/auth/otp/request      → sends 6-digit OTP
POST /api/v1/mobile/auth/otp/verify       → returns either:
        status = "authenticated"   + session token   (known phone)
        status = "signup_required" + signup_token     (new phone)
POST /api/v1/mobile/auth/signup/complete  → (new phone only) → session token
```

### 2.1 Request OTP

```http
POST /api/v1/mobile/auth/otp/request
Content-Type: application/json

{ "country": "ie", "phone": "871234561" }
```

- `country`: `ie` (Ireland → `+353`) or `ni` (Northern Ireland → `+44`). The
  server normalizes `country` + `phone` to E.164 (`+353871234561`).
- Response: `{ "expires_in": 300, "retry_after": 60 }`.
- OTP lifetime: **5 minutes**. Throttling: **1 request / minute** and **5 / hour**
  per phone (plus per-IP caps). Expect `429` if you hammer it.
- Production sends the Odoo-generated code through Twilio Programmable
  Messaging SMS. Odoo still verifies the code; Twilio Verify is not used.
- A successful request means Twilio accepted the SMS for delivery (normally
  `queued`), not that the handset has already received it.
- The SMS is only valid for the OTP lifetime: if the carrier cannot deliver it
  within those 5 minutes it is dropped, never delivered late. Ask the user to
  request a new code rather than waiting.

### 2.2 Verify OTP

```http
POST /api/v1/mobile/auth/otp/verify
Content-Type: application/json

{ "country": "ie", "phone": "871234561", "code": "000000", "application": "eastore", "device_id": "<your-device-uuid>", "platform": "android" }
```

- `application`, `device_id` and `platform` are **required**.
- `application` is `eastore` or `polonez` (otherwise `400 INVALID_APPLICATION`).
  It is fixed at build time: send the app you were built as, the same value on
  every login. One backend serves both apps, and the session records which one
  it belongs to — see the note under 2.4.
- `platform` must be `android` or `ios` (otherwise `400 INVALID_PLATFORM`).
- **Known phone** → `{ "status": "authenticated", "token": "est_...", ... }`.
- **New phone** → `{ "status": "signup_required", "signup_token": "..." }` →
  call `signup/complete`.
- Max **5** wrong attempts per code before it locks.

### 2.3 Complete signup (new phone only)

```http
POST /api/v1/mobile/auth/signup/complete
Content-Type: application/json

{ "signup_token": "...", "first_name": "Test", "terms_accepted": true, "application": "eastore", "device_id": "<your-device-uuid>", "platform": "android" }
```

Returns a session `token`. Like verify, `application` (`eastore`|`polonez`),
`device_id` and `platform` (`android`|`ios`) are **required**.

### 2.4 Using the session token

Send it on every authenticated call:

```
Authorization: Bearer est_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

The token has a **sliding 365-day expiry**. Every authenticated request validates
it; `GET /me`, called by the app on startup/resume, refreshes the expiry and
session activity. Manage sessions with `GET /auth/sessions`, `POST /auth/logout`
(this device), and `POST /auth/sessions/revoke-all`.

**One session per app.** Sessions are scoped to the `application` reported at
login, so the same account can be signed in to Eastore and Polonez at the same
time, on the same phone, without either logging the other out. `GET
/auth/sessions` returns `application` on every row so "Manage devices" can tell
them apart.

**Account-wide, not per app: "log out everywhere" and the device list.**
Sessions and communication preferences are per app, but `POST
/auth/sessions/revoke-all` deliberately revokes **every** session of the
account, Eastore and Polonez alike — it is a security action, and scoping it to
one app would weaken it exactly when it is needed. For the same reason `GET
/auth/sessions` lists the account's installs across both apps, so "Manage
devices" may show a phone that only has the other app on it.

**Active-session limit (max 2 devices per app by default).** A profile keeps at
most two active sessions **per application** — two Eastore installs and two
Polonez installs coexist. A third login *in the same app* revokes that app's
least recently used session, so that device gets `401 SESSION_REVOKED` on its
next call and must return to the login screen. Two consequences for the app:

- Persist `device_id` through a platform-specific mechanism whose reinstall
  and reset semantics have been verified. Do not rely on Android Keystore
  alone: uninstalling the app or clearing its data removes app-owned keys. On
  Android, evaluate a stable source such as `ANDROID_ID` with its signing-key,
  user, device, and reset scope, or use another explicitly tested recovery
  flow. A re-login with the same `device_id` replaces only that device's own
  session; a fresh id looks like a new device and costs the user one of their
  two slots.
- Re-validate the session when returning from background — do not skip the call
  because profile/card data is cached — so a signed-out device notices promptly.

---

## 3. Getting the OTP on STAGING (no real SMS)

Staging does **not** send real SMS by default. There are two ways to read the code:

### Option A — fixed test phones (recommended, self-service)

**Test phones** are configured on staging. When you request an OTP for any of
these exact phones, the code is **fixed** and no SMS is attempted:

| E.164 phone | `country` | `phone` field | OTP |
|---|---|---|---|
| `+353871234561` | `ie` | `871234561` | `000000` |
| `+442800000000` | `ni` | `2800000000` | `000000` |
| `+353870000000` | `ie` | `870000000` | `000000` |

So you can log in deterministically, for example as **John Smith** (a general
demo member dedicated to mobile testing):

```
request:  { "country": "ie", "phone": "871234561" }
verify:   { "country": "ie", "phone": "871234561", "code": "000000", "application": "eastore", "device_id": "dev-1", "platform": "android" }
→ status = "authenticated"
```

> **Do not use the `Integration Tester 01–05` accounts (`+35387999100x`).** They
> are reserved for POS / cash-register integration testing.
>
> Want to exercise the **signup** flow deterministically? Ask the backend team to
> add a fresh, non-existent number to `polonez_loyalty_mobile_api.otp_test_phones`.
> The singular legacy setting `otp_test_phone` is used only when the plural
> setting is empty.

### Option B — Mailtrap inbox (for any other phone)

For any phone other than the configured test phones, staging delivers the OTP
into a **Mailtrap** catch-all inbox (the OTP is emailed to a synthetic
`<phone-digits>@polonez.dev` address). This lets you exercise the **signup** flow
with fresh, never-seen numbers and still read the code. Ask the backend team for
access to the staging Mailtrap inbox.

---

## 4. Demo accounts (seeded by `polonez_loyalty_demo`)

Use these phones with the OTP flow. Phones are stored as E.164; pass them split as
`country` + local part (drop the `+353` / `+44`).

### General demo members — use these for mobile testing

| Name | Phone (E.164) | `phone` field | Trait |
|---|---|---|---|
| John Smith | `+353871234561` | `871234561` | regular, Ireland (**default test phone**) |
| Anna Kelly | `+353871234562` | `871234562` | regular, Ireland |
| Robert Murphy | `+353871234563` | `871234563` | regular, Ireland |
| Emily Ryan | `+353871234564` | `871234564` | regular, Ireland |
| Michael Doyle | `+353871234565` | `871234565` | staff member |
| Sarah Walsh | `+353871234566` | `871234566` | regular, Ireland |
| David Brennan | `+353871234567` | `871234567` | regular, Ireland |
| Laura Byrne | `+353871234568` | `871234568` | regular, Ireland |
| Thomas Fitz | `+353871234569` | `871234569` | country = Poland |
| Olivia Nolan | `+353871234570` | `871234570` | country = Poland |
| Points Rich Member | `+353871234571` | `871234571` | 2500 points |
| Points Small Balance | `+353871234572` | `871234572` | 399 points |
| Unverified Email Member | `+353871234573` | `871234573` | email not verified |
| Unverified DOB Member | `+353871234574` | `871234574` | no date of birth |
| Deleted Pending Member | `+353871234575` | `871234575` | deletion requested — logs in restricted, restore screen |

### Reserved — DO NOT use (POS / cash-register integration)

`Integration Tester 01–05` → `+353879991001 … +353879991005`. Leave these for the
POS team so mobile and POS testing don't collide.

---

## 5. Endpoint cheat-sheet

Authoritative request/response schemas are in `mobile.yaml` (Swagger UI). Quick map.
Paths use the canonical prefix; the `/odoo/...` fallback works too (see §1).

### Public (no auth)
| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/mobile/config` | Welcome voucher, legal doc versions, country/gender dropdowns (call before login). `?country=ie\|ni` (default `ie`) |
| GET | `/api/v1/mobile/legal/terms` | Terms & Conditions HTML. `?country=ie\|ni` (default `ie`) |
| GET | `/api/v1/mobile/legal/privacy` | Privacy Policy HTML. `?country=ie\|ni` (default `ie`) |
| GET | `/api/v1/mobile/offers/media/{kind}/{id}` | Public image/PDF media for visible offers/campaigns/banners |

### Auth (no token)
| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/mobile/auth/otp/request` | Request OTP |
| POST | `/api/v1/mobile/auth/otp/verify` | Verify OTP → token or signup_token |
| POST | `/api/v1/mobile/auth/signup/complete` | Finish signup → token |

### Authenticated (`Authorization: Bearer est_...`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/mobile/me` | Profile (incl. `current_country`, read-only `staff_discount` block for staff) |
| PATCH | `/api/v1/mobile/me` | Update profile (phone change rejected) |
| PUT | `/api/v1/mobile/me/country` | Switch operating country IE/NI (points/vouchers not transferred) |
| POST | `/api/v1/mobile/me/delete` | Request account deletion (72h cancellation window) |
| POST | `/api/v1/mobile/me/delete/cancel` | Restore an account pending deletion |
| POST | `/api/v1/mobile/me/email/request` | Request email verification code |
| POST | `/api/v1/mobile/me/email/verify` | Verify email code |
| GET/PATCH | `/api/v1/mobile/me/preferences/{application}` | Read/update Eastore or Polonez communication preferences |
| GET | `/api/v1/mobile/me/card` | Digital card + points, conversion progress/date, currency + daily QR batch (current country) |
| GET | `/api/v1/mobile/me/points-history` | Wallet history, cursor-paginated (filters: `limit`, `cursor`); current country, 2 years back |
| POST | `/api/v1/mobile/me/visits/{entry_id}/feedback` | Rate one visit from the history (once per visit) |
| GET | `/api/v1/mobile/vouchers` | List my vouchers, current country (filters: `status`, `amount`, `q`) |
| GET | `/api/v1/mobile/vouchers/{code}` | One of my vouchers (404 if not mine) |
| POST | `/api/v1/mobile/vouchers/claim` | Claim a printed voucher by code |
| GET | `/api/v1/mobile/offers/campaigns` | Visible offer campaigns for current country |
| GET | `/api/v1/mobile/offers` | Paginated offers + banners (filters: `campaign_id`, `limit`, `offset`) |
| GET | `/api/v1/mobile/offers/{id}` | Visible offer detail (404 if expired/cross-country) |
| GET | `/api/v1/mobile/stores` | Stores for current country, with format/facility/favourite filters |
| POST/PUT/DELETE | `/api/v1/mobile/stores/{code}/favorite` | Add/remove a favourite store |
| PUT | `/api/v1/mobile/me/push-registration` | Register/refresh this install's FCM token |
| DELETE | `/api/v1/mobile/me/push-registration` | Stop targeting this install |
| GET | `/api/v1/mobile/auth/sessions` | List active sessions |
| POST | `/api/v1/mobile/auth/logout` | Revoke this device's session |
| POST | `/api/v1/mobile/auth/sessions/revoke-all` | Revoke all sessions |

Standard registration may leave `date_of_birth` empty; the member then remains
unverified. When the date is supplied through `PATCH /me`, the member must be
between 18 and 150 years old, inclusive. Dates outside that range return
`400 INVALID_AGE` and cannot produce a verified profile.

---

## 6. Quick start (cURL)

```bash
# Canonical prefix (recommended). For the /odoo fallback, append /odoo to BASE.
BASE=https://stage.odoo-stage.polonez.dev

# 1. public config (no auth)
curl -s $BASE/api/v1/mobile/config | jq

# 2. request OTP for a test phone (no SMS, fixed code 000000)
curl -s -X POST $BASE/api/v1/mobile/auth/otp/request \
  -H 'Content-Type: application/json' \
  -d '{"country":"ie","phone":"871234561"}' | jq

# 3. verify → get session token (application + device_id + platform are required)
TOKEN=$(curl -s -X POST $BASE/api/v1/mobile/auth/otp/verify \
  -H 'Content-Type: application/json' \
  -d '{"country":"ie","phone":"871234561","code":"000000","application":"eastore","device_id":"dev-1","platform":"android"}' \
  | jq -r .token)

# 4. authenticated call
curl -s $BASE/api/v1/mobile/me -H "Authorization: Bearer $TOKEN" | jq
curl -s $BASE/api/v1/mobile/me/preferences/eastore -H "Authorization: Bearer $TOKEN" | jq
curl -s -X PATCH $BASE/api/v1/mobile/me/preferences/eastore \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"push_notifications":false,"email_newsletter":true}' | jq
curl -s $BASE/api/v1/mobile/me/card -H "Authorization: Bearer $TOKEN" | jq
curl -s $BASE/api/v1/mobile/stores -H "Authorization: Bearer $TOKEN" | jq
curl -s "$BASE/api/v1/mobile/stores?format=eastore&has_butchers=true" \
  -H "Authorization: Bearer $TOKEN" | jq
curl -s -X POST $BASE/api/v1/mobile/stores/ARTAN/favorite \
  -H "Authorization: Bearer $TOKEN" | jq
curl -s $BASE/api/v1/mobile/offers -H "Authorization: Bearer $TOKEN" | jq
```

### Point conversion progress

`GET /me/card` always includes `points_conversion`. Conversion rules are fixed:
100 points = 1 unit of the current currency (EUR in IE, GBP in NI), and a minimum
of 400 points is required. Whole currency units are converted into vouchers of
up to 10 units each, with a smaller final voucher for the remaining whole units;
the sub-unit remainder stays on the balance. For example, 1,450 points produces
vouchers worth 10 and 4, leaving 50 points. Converted vouchers stay valid for
one year from the conversion date. The block exposes `minimum_points` (400), the
`points_remaining` to reach it, the current balance value in
`points_balance_value_cents` (one point = one cent/penny), and `next_conversion_date`
(`null` when no future date is planned). Conversion dates are global for IE and NI;
only the balance/progress and currency use the member's current country. Conversion
runs automatically at 00:00 on each planned date.

### Points history

> **Breaking change (SO20-3003).** The response shape changed and the endpoint is
> not versioned, so a client written against the previous one shows an empty
> screen rather than an error — `transactions` simply is not there any more.
> What moved:
>
> | before | now |
> |---|---|
> | `{"transactions": [...]}` | `{"items": [...], "next_cursor": …, "has_more": …}` |
> | `date` | `occurred_at` |
> | `store_name` (string) | `store` (object with `code`, `name`, `format`, or `null`) |
>
> Everything else on a row is additive. New query params `limit` and `cursor`
> drive lazy loading; without them you get the newest 20 rows.

`GET /me/points-history` returns the member's wallet history for the current
country, newest first, two years back. Because wallets are isolated per country,
switching IE/NI switches the whole history with it.

One row per event, and everything about a visit stays inside that row. A purchase
carries its points, the vouchers spent on it (`vouchers_used`) and the vouchers it
handed out (`vouchers_earned`) — there are no extra zero-point rows to stitch
together. Rows with `points: 0` are genuine: a basket too small to earn anything
is still a visit worth showing. `type` is `purchase`, `conversion` (Head Office
turning points into vouchers — always negative points, dated the day HO scheduled)
or `adjustment` (a manual back-office correction, which may have no store).

A purchase also carries `staff_discount_cents`: the staff discount confirmed as
applied to that receipt in minor currency units. A positive value is reconciled
against the matching get-member basket. `0` means either no staff discount or
that application could not be confirmed; do not show the chip in either case.
Non-purchase rows return `null`. Never infer this checkout-time value from
`/me.staff_discount`, which is the member's current rate and can change later.

`occurred_at` is UTC and comes from the till receipt, not from when the finalize
call reached Odoo — a till replaying a queued receipt keeps its real time. A
conversion uses midnight on the date Head Office scheduled; several missed
dates collapse into one entry using the latest of them. If the wallet already
has activity at or after that time, the conversion is timestamped one second
after its latest entry so the debit follows the activity that funded it. An
immediate conversion uses the day it ran, with the same ordering rule.

Paging uses an opaque `cursor`, not an offset: new rows land at the top while the
member scrolls, and an offset would repeat or skip rows across pages. Pass the
previous response's `next_cursor` to load more; omit it for the newest page, which
is what pull-to-refresh does. A malformed cursor is a 400 `INVALID_CURSOR` rather
than a silent restart from the top. `limit` defaults to 20 and is clamped to 100.

---

## 7. Rating a visit

Every `purchase` row of `GET /me/points-history` carries two additive fields:
`can_rate` and `feedback`. Render the rating entry point when `can_rate` is true,
the rating already given when `feedback` is set, and nothing when both say no.

`POST /me/visits/{entry_id}/feedback` submits it. `entry_id` is the history row's
`id`, so no extra lookup is needed. A visit can be rated **once**: there is no
edit and no delete, and a second attempt is `409 VISIT_ALREADY_RATED`.

A visit is rateable when it is the member's own `purchase`, the till resolved to a
Store Locator shop (the question names the store), and the receipt is inside the
rating window — 90 days by default. Anything else is `403 VISIT_NOT_RATEABLE`
with `details.reason` set to `not_a_purchase`, `no_store` or `outside_window`. A
visit in the other country never appears in the first place: feedback follows the
shop's country, and the history is read per country. The endpoint holds the same
line, so an `entry_id` cached from before a country switch comes back `404`
rather than being rated out of view.

The form has three criteria — `overall`, `staff`, `product` — each 1-5 and
**none preselected**. Keep Submit disabled until all three are set: a default of 5
would turn one tap into 5/5/5 and make every store average meaningless. A comment
is mandatory when any criterion is at or below the low-rating threshold (3), and
optional otherwise; either way it must be between the configured minimum and
1,000 characters.

`/config` carries the rules so both sides enforce the same values:

```json
"feedback": {
  "comment_min_chars": 5,
  "comment_max_chars": 1000,
  "low_rating_threshold": 3,
  "rating_window_days": 90
}
```

The 5-character minimum is the only hard floor. Use the room above it for
progressive encouragement — nudge for more detail while the comment is short,
acknowledge a fuller one — but never block Submit on that nudge. Validation
failures come back as `422` with a single `error.code`
(`INVALID_RATING`, `COMMENT_REQUIRED`, `COMMENT_TOO_SHORT`, `COMMENT_TOO_LONG`)
and `details.field` naming the input to highlight.

Tell the member before they submit that the business may contact them about the
feedback, and show `message` from the `201` response verbatim on success:
*Thank you for your feedback. We will contact you if needed.*

---

## 8. Communication preferences

The `{application}` in the path must match the app your session was issued to.
Reading or writing the other app's preferences returns `403
APPLICATION_MISMATCH` — an Eastore build cannot switch off Polonez push.

Preferences are scoped to the authenticated account and the application path
value (`eastore` or `polonez`). They are shared by all devices, unchanged when
the member switches between IE and NI, and independent between the two apps.

For users without a stored row, `GET /me/preferences/{application}` creates and
returns these defaults:

```json
{
  "application": "eastore",
  "push_notifications": true,
  "email_newsletter": false,
  "receive_sms": false,
  "is_profile_verified": false
}
```

`PATCH` accepts one or more boolean fields and returns the same complete shape.
Unknown fields, non-booleans, and an empty body are rejected with `400`.
Enabling `email_newsletter` or `receive_sms` for an unverified profile returns
`409 PROFILE_NOT_VERIFIED` with the blocked fields in `error.details.fields`;
disabling either field is always allowed.

`push_notifications` is the account-level preference. The mobile app must still
request/check the current device's OS notification permission, and the sender
must require both this preference and valid permission/token for the target
device. A system denial on one device must never overwrite the account value or
another device's permission.

Every effective change is audited server-side with old/new values, app, member,
time, current IE/NI region, session device/platform, and source. Marketing
senders must call `loyalty.mobile.preference.communication_allowed()` immediately
before delivery; it re-checks both profile verification and the latest value.
This addon does not currently contain a marketing delivery service. Transactional
OTP and email-verification messages intentionally bypass marketing preferences.
When an account is permanently deleted, the current preferences and their whole
consent audit history are removed with it.

---

## 9. Push registration

```http
PUT /api/v1/mobile/me/push-registration
Authorization: Bearer est_...
Content-Type: application/json

{ "token": "<FCM registration token>" }
```

- The body carries **only** the token. Account, app, device and platform come
  from your session, so nothing else can be spoofed.
- Call it after login, on every token rotation, and on resume. It is idempotent;
  an unchanged token seen again shortly after is acknowledged without a write.
- `DELETE` on the same path stops targeting this install — use it when the OS
  permission is withdrawn. It is device-local and does **not** flip the
  account's `push_notifications` preference, so other devices keep working.
- Registrations are revoked server-side on logout, logout-all, phone change,
  session eviction and account deletion. Register again once a new session
  exists.
- Turning `push_notifications` off does not drop the token: consent is checked
  at send time, so switching it back on works without a new OS prompt.
- **`409 REGISTRATION_CONFLICT` means retry, not failure.** FCM can hand the same
  token to a restored device, and if both installs register it at the same moment
  one of them loses. Nothing is broken and the session is still valid — just send
  the same `PUT` again later, on the next resume. Do not sign the user out.

---

## 10. Common errors

| Code | Meaning |
|---|---|
| `400` | Bad request (e.g. invalid `country`, malformed phone, missing field) |
| `401` | Missing / invalid / expired Bearer token (`UNAUTHORIZED`), or signed out by the active-session limit (`SESSION_REVOKED`) |
| `403` | Account scheduled for deletion (`ACCOUNT_DELETION_PENDING`) — see §14; or a preferences path naming the other app (`APPLICATION_MISMATCH`) — see §8 |
| `409` | Conflict — a voucher already claimed, or a push token being claimed by another install (`REGISTRATION_CONFLICT`, retry) |
| `429` | OTP rate limit — wait `retry_after` seconds |
| `503` | OTP delivery provider unavailable |

Errors carry a machine-readable code (e.g. `INVALID_COUNTRY`, `INVALID_PLATFORM`,
`INVALID_JSON`, `OTP_RATE_LIMIT_REQUEST`, `OTP_LOCKED`, `SESSION_REVOKED`) — see
the error schemas in `mobile.yaml`.

---

## 11. Vouchers

The app surfaces vouchers; **redemption happens at the till** (Cash Register
API), not in the app. Money fields are in cents.

### Listing

`GET /vouchers` returns the member's vouchers, soonest-to-expire first:

```bash
curl -s "$BASE/api/v1/mobile/vouchers" -H "Authorization: Bearer $TOKEN" | jq
```

- `?status=` — comma-separated `active,issued,used,expired,revoked`. Default
  `active,issued` (usable now/soon). Pass e.g. `?status=used,expired` for history.
- `?amount=` — exact discount value in cents (e.g. `500` = €5).
- `?q=` — substring over voucher description and code.

`GET /vouchers/{code}` returns a single owned voucher (`404 NOT_FOUND` if it
isn't the member's).

### Claiming a printed voucher

`POST /vouchers/claim {"code":"..."}` attaches an anonymous voucher scanned from
a paper receipt to the member:

- Must be currently **anonymous** and **usable** (`Active`/`Issued`).
- Re-claiming your own → `200` (idempotent).
- Belongs to another member → `409 ALREADY_CLAIMED`.
- Used/expired/revoked → `400 VOUCHER_NOT_CLAIMABLE`. Unknown → `404 VOUCHER_NOT_FOUND`.

### Voucher fields & statuses

DTO: `code`, `type`, `status`, `description`, `discount_cents`,
`min_purchase_cents`, `valid_from`, `valid_until`, `received_at`, `redeemed_at`,
`receipt`, `qr_code_payload`, `printed`.

Status lifecycle: `Issued` → `Active` → `Used` / `Expired` / `Revoked`.

### How vouchers are distributed

| Type | Issued | Audience | Validity |
|---|---|---|---|
| `welcome` | once per member per country: on signup, or first switch to a country without a previous welcome voucher | member | from issuance, 14 days |
| `x_off_y` | at the till on spend thresholds (rules) | anonymous and/or registered | per rule |
| `birthday` | daily cron around the member's birthday (once/year) | member | birthday window |
| `individual` | manually from the back office | member | per issuance |

Seeded spend-threshold rules: **€5 off €25** (anonymous, 14d), **€5 off €25**
(registered, 365d), **€10 off €50** (registered, 365d). A single receipt can
yield multiple vouchers. Verification gates spending/redeeming of non-welcome
vouchers; the welcome voucher is usable even before full verification.

---

## 12. Offers

Promotional offers are country-scoped to the member's `current_country`. The
backend also returns country-less campaigns/banners that are intended for both
IE and NI. Expired, unpublished, inactive, or cross-country records are not
served.

### Campaigns

`GET /offers/campaigns` returns cards for the Home carousel and listing selector:

```bash
curl -s "$BASE/api/v1/mobile/offers/campaigns" \
  -H "Authorization: Bearer $TOKEN" | jq
```

Each campaign includes:

- `id`, `title`, `description`, `country` (`null` = both countries)
- `image_url` — mobile-relative media URL, e.g. `/offers/media/campaign-image/101`
- `leaflet_url` — optional campaign PDF leaflet
- `valid_from`, `valid_until`
- `offer_count`

### Offers listing

`GET /offers` returns paginated offers plus active standalone banners:

```bash
curl -s "$BASE/api/v1/mobile/offers?limit=12&offset=0" \
  -H "Authorization: Bearer $TOKEN" | jq
```

Query params:

- `campaign_id` — optional campaign id filter for offers.
- `limit` — page size, default `12`, capped at `100`.
- `offset` — pagination offset, default `0`.

Response fields:

- `offers` — sorted by campaign, priority DESC, title ASC.
- `banners` — standalone listing banners, each with image and optional leaflet.
- `total` — unpaginated count of matching offers.
- `limit`, `offset` — effective pagination values.

Offer DTO highlights:

- `has_price=true` → `price` object is present (`text_1`, `value_1`, `text_2`,
  `value_2`, `unit`). Values are strings because they are display copy.
- `has_price=false` → `price=null`; app should show the “Find the price in the
  store” fallback.
- `promotion_type` is optional and contains `code`, `name`, `badge_url`.

### Offer detail

`GET /offers/{id}` returns one visible offer. It returns `404 NOT_FOUND` if the
offer is unknown, expired, unpublished, or not visible for the member's current
country.

### Offer media

`GET /offers/media/{kind}/{id}` is public (no Bearer token) so native image/PDF
loaders can fetch promotional assets directly. It only serves visible/active
records and returns 404 otherwise.

Supported `kind` values:

- `campaign-image`
- `campaign-leaflet`
- `offer-image`
- `banner-image`
- `banner-leaflet`
- `promotion-badge`

The URLs returned by the API are **mobile-relative** (`/offers/media/...`). Prefix
them with the same API base you use for JSON calls, e.g.
`https://stage.odoo-stage.polonez.dev/api/v1/mobile`.

---

## 13. Stores and opening hours

`GET /stores` returns active shops for the member's `current_country`, both
Polonez and Eastore, ordered by name.

```bash
curl -s "$BASE/api/v1/mobile/stores" -H "Authorization: Bearer $TOKEN" | jq
```

Query filters:

- `format=all|polonez|eastore` — single-select brand filter. Omitted or `all`
  returns both brands.
- `favorite=true` — only member favourites. `favourite=true` is also accepted.
- `has_off_licence=true` — only shops with off licence.
- `has_freshly_baked=true` — only shops with freshly baked products.
- `has_butchers=true` — only shops with butchers/fresh meat.

Boolean filters are app toggles: `true`, `1`, `yes`, `on` enable the filter;
`false`, `0`, `no`, `off`, empty, or omitted mean no filter. Enabled filters are
combined with AND.

Examples:

```bash
curl -s "$BASE/api/v1/mobile/stores?format=eastore" \
  -H "Authorization: Bearer $TOKEN" | jq
curl -s "$BASE/api/v1/mobile/stores?has_off_licence=true&has_freshly_baked=true" \
  -H "Authorization: Bearer $TOKEN" | jq
curl -s "$BASE/api/v1/mobile/stores?favorite=true" \
  -H "Authorization: Bearer $TOKEN" | jq
```

Store DTO fields:

- identity/map: `code`, `name`, `format`, `country`, `address`, `maps_url`,
  `latitude`, `longitude`.
- facilities/favourite: `has_off_licence`, `has_freshly_baked`, `has_butchers`,
  `is_favorite`.
- `opening_hours_display` — human-readable text for display.
- `opening_hours_source` — `website`, `manual`, or `default`.
- `opening_hours.timezone` — derived from country (`ie` → `Europe/Dublin`,
  `ni` → `Europe/London`); it is not edited independently in the back end.
- `opening_hours.weekly` — structured schedule keyed by `mon` … `sun`, each day
  containing zero or more `["HH:MM", "HH:MM"]` intervals.

Example:

```json
{
  "code": "FONTH",
  "name": "Fonthill",
  "has_off_licence": true,
  "has_freshly_baked": true,
  "has_butchers": false,
  "is_favorite": false,
  "opening_hours_display": "Mon-Wed 09:00-20:00; Thu-Sat 09:00-21:00; Sun 10:00-20:00",
  "opening_hours_source": "website",
  "opening_hours": {
    "timezone": "Europe/Dublin",
    "weekly": {
      "mon": [["09:00", "20:00"]],
      "tue": [["09:00", "20:00"]],
      "wed": [["09:00", "20:00"]],
      "thu": [["09:00", "21:00"]],
      "fri": [["09:00", "21:00"]],
      "sat": [["09:00", "21:00"]],
      "sun": [["10:00", "20:00"]]
    }
  }
}
```

Favourite stores:

```bash
# add to favourites (idempotent; empty body means true)
curl -s -X POST "$BASE/api/v1/mobile/stores/FONTH/favorite" \
  -H "Authorization: Bearer $TOKEN" | jq

# explicitly set state; PUT has the same semantics
curl -s -X POST "$BASE/api/v1/mobile/stores/FONTH/favorite" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"favorite":false}' | jq

# remove from favourites
curl -s -X DELETE "$BASE/api/v1/mobile/stores/FONTH/favorite" \
  -H "Authorization: Bearer $TOKEN" | jq
```

The favourite endpoint returns `{"store": ...}` with the same Store DTO and the
updated `is_favorite` value. It is scoped to the member's current country, so a
store from the other country returns `404 NOT_FOUND`.

For shops where no store-specific source was found, the backend currently uses
`opening_hours_source=default` with `Mon-Sat 10:00-20:00; Sun 11:00-19:00`.

---

## 14. Deleting an account, and taking it back

Deletion is a two-step affair: closing the account is instant, erasing it is not.

### Requesting it

`POST /me/delete` closes the account immediately. Every session, push
registration and QR token is revoked in that call, so the app must drop its
token and return to the unauthenticated flow, and push stops arriving on every
install. The response carries the window:

```json
{
  "deleted": true,
  "requested_at": "2026-06-11T21:43:39Z",
  "eligible_for_deletion_at": "2026-06-14T21:43:39Z"
}
```

Nothing is erased yet. Points, vouchers and history are all still there.

### The restore screen

Logging in with the same number during the window works normally, and
`/auth/otp/verify` answers with `account_state: "deletion_pending"` plus
`requested_at` and `eligible_for_deletion_at`. Route that to the restore screen.

The token that comes with it is **restricted**: only `POST /me/delete/cancel`
and `POST /auth/logout` accept it. Everything else answers
`403 ACCOUNT_DELETION_PENDING`, with the same two timestamps in
`error.details` — so an app that cold-starts holding a restricted token can
draw the screen without a readable profile endpoint.

Two things to get right in the copy:

- Say **"you have until"**, not "will be deleted at". `eligible_for_deletion_at`
  is when the daily cleanup becomes *allowed* to run, so the real deadline is up
  to a day later.
- **Do not hide the restore button when the timer hits zero.** Cancellation keeps
  working until the cleanup has actually started. Keep offering it until the API
  refuses.

### Restoring

`POST /me/delete/cancel` brings the account back exactly as it was — points,
vouchers, history, profile fields and the verified email — and returns the
profile. No re-login: the same token is an ordinary session from that moment,
because the restriction came from the account's state, not from the token.

Two races to handle:

- `409 ACCOUNT_DELETION_NOT_PENDING` — already cancelled from another device.
  Continue to the main screen.
- `401` — the cleanup won: the account and its sessions are gone. Route to fresh
  signup.

### After the window

The cleanup erases the account irreversibly and it can never be reactivated.
Registering the same number afterwards creates a **new** account with a new
Loyalty ID, empty wallets and none of the previous vouchers or history (it may
receive a new welcome voucher — that is accepted).

There is no way to tell a returning member from a new one: `/auth/otp/verify`
simply answers `signup_required`. Nothing is retained to recognise them, by
design — which is exactly why the deadline belongs on the restore screen.


## FAQ (SO20-3147)

Available after deploying `polonez_loyalty_mobile_api` 18.0.30.0.0 or later.

`GET /api/v1/mobile/faq?country=ie|ni` is public and requires an explicit country.
The `/odoo/api/v1/mobile/faq` compatibility route is also available.
Odoo: Loyalty → Administration → FAQ (system administrators, matching Legal Documents).
Each country has its own draft. Edit categories, icons, question/answer order and
support details; **Publish FAQ** replaces the public snapshot atomically. Saving,
disabling or deleting draft items does not change the published content. Empty and
disabled categories and disabled questions are omitted at publication. An empty FAQ
cannot be published; use **Unpublish** to withdraw it. Version increments automatically.

The initial import contains 45 questions in five categories from
`FAQ-app-draft-reference.docx`: Loyalty program, Vouchers, Points, Offers, Account.
App support is the bottom support block. IE starts unpublished; NI starts empty and
unpublished. This is draft wording, including euro amounts and app behavior that
must be reviewed before publication. Contacts are intentionally empty until configured.
Seed records use `noupdate` so module upgrades preserve editorial changes.

App integration: retain the supplied Help centre and category accordion designs.
Fetch the entire FAQ on entry and country change; cache keys include country.
Immediately clear content on country change and ignore older in-flight responses.
Search question text and the plain text of HTML answers locally across categories.
Search results should show the category and open the matching question.
Render `answer_html` with the app's safe rich-text renderer. Unknown category icons
use a generic help icon; do not hardcode the five categories from the screenshot.
Show a clear empty state for empty categories, and separate retry UI for network errors.
Support email and WhatsApp actions appear only when supplied. The API returns null
support when unpublished.
