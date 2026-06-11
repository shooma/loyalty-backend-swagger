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
| **Canonical prefix** | `/api/v1/mobile/...` |
| **Odoo-compat prefix** | `/odoo/api/v1/mobile/...` (use if a proxy/gateway needs the `/odoo` root) |
| **Content type** | `application/json` |
| **DB selection** | host-based (`dbfilter`), nothing to send — just use the staging host |

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

{ "country": "ie", "phone": "871234561", "code": "000000", "device_id": "<your-device-uuid>" }
```

- **Known phone** → `{ "status": "authenticated", "token": "est_...", ... }`.
- **New phone** → `{ "status": "signup_required", "signup_token": "..." }` →
  call `signup/complete`.
- Max **5** wrong attempts per code before it locks.

### 2.3 Complete signup (new phone only)

```http
POST /api/v1/mobile/auth/signup/complete
Content-Type: application/json

{ "signup_token": "...", "first_name": "Test", "terms_accepted": true, "device_id": "<your-device-uuid>" }
```

Returns a session `token`.

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

Authoritative request/response schemas are in `mobile.yaml` (Swagger UI). Quick map:

### Public (no auth)
| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/mobile/config` | Welcome voucher, legal doc versions, country/gender dropdowns (call before login) |
| GET | `/api/v1/mobile/legal/terms` | Terms & Conditions HTML |
| GET | `/api/v1/mobile/legal/privacy` | Privacy Policy HTML |

### Auth (no token)
| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/mobile/auth/otp/request` | Request OTP |
| POST | `/api/v1/mobile/auth/otp/verify` | Verify OTP → token or signup_token |
| POST | `/api/v1/mobile/auth/signup/complete` | Finish signup → token |

### Authenticated (`Authorization: Bearer est_...`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/mobile/me` | Profile |
| PATCH | `/api/v1/mobile/me` | Update profile (phone change rejected) |
| POST | `/api/v1/mobile/me/delete` | Soft-delete account |
| POST | `/api/v1/mobile/me/email/request` | Request email verification code |
| POST | `/api/v1/mobile/me/email/verify` | Verify email code |
| GET | `/api/v1/mobile/me/card` | Digital card + points + daily QR batch |
| GET | `/api/v1/mobile/me/points-history` | Last 50 point-earning transactions |
| GET | `/api/v1/mobile/auth/sessions` | List active sessions |
| POST | `/api/v1/mobile/auth/logout` | Revoke this device's session |
| POST | `/api/v1/mobile/auth/sessions/revoke-all` | Revoke all sessions |

---

## 6. Quick start (cURL)

```bash
BASE=https://stage.odoo-stage.polonez.dev

# 1. public config (no auth)
curl -s $BASE/api/v1/mobile/config | jq

# 2. request OTP for the test phone (no SMS, fixed code 000000)
curl -s -X POST $BASE/api/v1/mobile/auth/otp/request \
  -H 'Content-Type: application/json' \
  -d '{"country":"ie","phone":"871234561"}' | jq

# 3. verify → get session token
TOKEN=$(curl -s -X POST $BASE/api/v1/mobile/auth/otp/verify \
  -H 'Content-Type: application/json' \
  -d '{"country":"ie","phone":"871234561","code":"000000","device_id":"dev-1"}' \
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

Errors carry a machine-readable code (e.g. `INVALID_COUNTRY`, `OTP_RATE_LIMIT_REQUEST`,
`OTP_LOCKED`) — see the error schemas in `mobile.yaml`.
