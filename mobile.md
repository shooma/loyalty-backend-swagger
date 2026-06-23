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

### Option A — fixed test phone (recommended, self-service)

A **test phone** is configured on staging. When you request an OTP for that exact
phone, the code is **fixed** and no SMS is attempted:

| System parameter | Value |
|---|---|
| `polonez_loyalty_mobile_api.otp_test_phone` | `+353871234561` |
| `polonez_loyalty_mobile_api.otp_test_code` | `000000` |

So you can log in deterministically as **John Smith** (a general demo member
dedicated to mobile testing):

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

For any phone other than the test phone, staging delivers the OTP into a
**Mailtrap** catch-all inbox (the OTP is emailed to a synthetic
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
| GET | `/api/v1/mobile/me` | Profile (incl. `current_country`) |
| PATCH | `/api/v1/mobile/me` | Update profile (phone change rejected) |
| PUT | `/api/v1/mobile/me/country` | Switch operating country IE/NI (points/vouchers not transferred) |
| POST | `/api/v1/mobile/me/delete` | Soft-delete account |
| POST | `/api/v1/mobile/me/email/request` | Request email verification code |
| POST | `/api/v1/mobile/me/email/verify` | Verify email code |
| GET | `/api/v1/mobile/me/card` | Digital card + points + currency + daily QR batch (current country) |
| GET | `/api/v1/mobile/me/points-history` | Last 50 point-earning transactions (current country) |
| GET | `/api/v1/mobile/vouchers` | List my vouchers, current country (filters: `status`, `amount`, `q`) |
| GET | `/api/v1/mobile/vouchers/{code}` | One of my vouchers (404 if not mine) |
| POST | `/api/v1/mobile/vouchers/claim` | Claim a printed voucher by code |
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

# 2. request OTP for the test phone (no SMS, fixed code 000000)
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
curl -s $BASE/api/v1/mobile/me/card -H "Authorization: Bearer $TOKEN" | jq
```

---

## 7. Common errors

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

## 8. Vouchers

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
