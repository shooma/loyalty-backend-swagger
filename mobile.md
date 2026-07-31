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

### 2.2 Verify OTP

```http
POST /api/v1/mobile/auth/otp/verify
Content-Type: application/json

{ "country": "ie", "phone": "871234561", "code": "000000", "device_id": "<your-device-uuid>", "platform": "android" }
```

- `device_id` and `platform` are **required**. `platform` must be `android` or
  `ios` (otherwise `400 INVALID_PLATFORM`).
- **Known phone** → `{ "status": "authenticated", "token": "est_...", ... }`.
- **New phone** → `{ "status": "signup_required", "signup_token": "..." }` →
  call `signup/complete`.
- Max **5** wrong attempts per code before it locks.

### 2.3 Complete signup (new phone only)

```http
POST /api/v1/mobile/auth/signup/complete
Content-Type: application/json

{ "signup_token": "...", "first_name": "Test", "terms_accepted": true, "device_id": "<your-device-uuid>", "platform": "android" }
```

Returns a session `token`. Like verify, `device_id` and `platform`
(`android`|`ios`) are **required**.

### 2.4 Using the session token

Send it on every authenticated call:

```
Authorization: Bearer est_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

The token has a **sliding 365-day expiry** (renewed on each use). Manage sessions
with `GET /auth/sessions`, `POST /auth/logout` (this device),
`POST /auth/sessions/revoke-all`.

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
verify:   { "country": "ie", "phone": "871234561", "code": "000000", "device_id": "dev-1" }
→ status = "authenticated"
```

> **Do not use the `Integration Tester 01–05` accounts (`+35387999100x`).** They
> are reserved for POS / cash-register integration testing.
>
> Want to exercise the **signup** flow deterministically? Ask the backend team to
> point `otp_test_phone` at a fresh, non-existent number.

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
| Deleted Pending Member | `+353871234575` | `871234575` | soft-deleted account |

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
| POST | `/api/v1/mobile/me/delete` | Soft-delete account |
| POST | `/api/v1/mobile/me/email/request` | Request email verification code |
| POST | `/api/v1/mobile/me/email/verify` | Verify email code |
| GET/PATCH | `/api/v1/mobile/me/preferences/{application}` | Read/update Eastore or Polonez communication preferences |
| GET | `/api/v1/mobile/me/card` | Digital card + points, conversion progress/date, currency + daily QR batch (current country) |
| GET | `/api/v1/mobile/me/points-history` | Last 50 point-earning transactions (current country) |
| GET | `/api/v1/mobile/vouchers` | List my vouchers, current country (filters: `status`, `amount`, `q`) |
| GET | `/api/v1/mobile/vouchers/{code}` | One of my vouchers (404 if not mine) |
| POST | `/api/v1/mobile/vouchers/claim` | Claim a printed voucher by code |
| GET | `/api/v1/mobile/offers/campaigns` | Visible offer campaigns for current country |
| GET | `/api/v1/mobile/offers` | Paginated offers + banners (filters: `campaign_id`, `limit`, `offset`) |
| GET | `/api/v1/mobile/offers/{id}` | Visible offer detail (404 if expired/cross-country) |
| GET | `/api/v1/mobile/offers/media/{kind}/{id}` | Public image/PDF media for visible offers/campaigns/banners |
| GET | `/api/v1/mobile/stores` | Stores for current country, with format/facility/favourite filters |
| POST/PUT/DELETE | `/api/v1/mobile/stores/{code}/favorite` | Add/remove a favourite store |
| GET | `/api/v1/mobile/auth/sessions` | List active sessions |
| POST | `/api/v1/mobile/auth/logout` | Revoke this device's session |
| POST | `/api/v1/mobile/auth/sessions/revoke-all` | Revoke all sessions |

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

# 3. verify → get session token (device_id + platform are required)
TOKEN=$(curl -s -X POST $BASE/api/v1/mobile/auth/otp/verify \
  -H 'Content-Type: application/json' \
  -d '{"country":"ie","phone":"871234561","code":"000000","device_id":"dev-1","platform":"android"}' \
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
100 points = EUR 1, a minimum of 400 points (EUR 4) is required, vouchers are issued
in EUR 10 steps with the sub-euro remainder kept on the balance, and converted
vouchers stay valid for one year. The block exposes `minimum_points` (400), the
`points_remaining` to reach it, the current balance value in
`points_balance_value_cents` (one point = one cent/penny), and `next_conversion_date`
(`null` when no future date is planned). Conversion dates are global for IE and NI;
only the balance/progress and currency use the member's current country. Conversion
runs automatically at 00:00 on each planned date.

---

## 7. Communication preferences

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
At account anonymisation (180 days after deletion), current preferences are
removed and device identifiers are erased from the retained consent history.

---

## 8. Common errors

| Code | Meaning |
|---|---|
| `400` | Bad request (e.g. invalid `country`, malformed phone, missing field) |
| `401` | Missing / invalid / expired Bearer token |
| `429` | OTP rate limit — wait `retry_after` seconds |
| `503` | OTP delivery provider unavailable |

Errors carry a machine-readable code (e.g. `INVALID_COUNTRY`, `INVALID_PLATFORM`,
`INVALID_JSON`, `OTP_RATE_LIMIT_REQUEST`, `OTP_LOCKED`) — see the error schemas in
`mobile.yaml`.

---

## 9. Vouchers

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
| `welcome` | once per member, on sign-up completion | member | from receipt, 14 days |
| `x_off_y` | at the till on spend thresholds (rules) | anonymous and/or registered | per rule |
| `birthday` | daily cron around the member's birthday (once/year) | member | birthday window |
| `individual` | manually from the back office | member | per issuance |

Seeded spend-threshold rules: **€5 off €25** (anonymous, 14d), **€5 off €25**
(registered, 365d), **€10 off €50** (registered, 365d). A single receipt can
yield multiple vouchers. Verification gates spending/redeeming of non-welcome
vouchers; the welcome voucher is usable even before full verification.

---

## 10. Offers

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

## 11. Stores and opening hours

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
