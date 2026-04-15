# Polonez Loyalty Stub API

This file documents the current stub behavior of `polonez_loyalty` for POS integrators.

## Base URL

- Primary (Stage): `https://odoo-stage.polonez.dev`
- Production: `https://erp.polonez.ie`
- Swagger UI: `https://shooma.github.io/loyalty-backend-swagger/`

## Endpoints

- `POST /api/v1/loyalty/get-member`
- `POST /api/v1/loyalty/finalize-order`

## Monetary Units

All monetary fields are sent in minor units (cents), as integers.

- `700` = `EUR 7.00`
- `1400` = `EUR 14.00`

## Voucher Code Format

- Voucher code is opaque and must not expose internal semantics.
- Current format: exactly 20 digits.

## Authorization

Use `Authorization: Bearer <token>`.

Token scopes:
- POS-scoped token (`polonez.loyalty.token` linked to POS): `X-Pos-Id` is optional.
- Store-scoped token (`polonez.loyalty.token` linked to shop): `X-Pos-Id` is required.

If `X-Pos-Id` is present and `pos_id` is present in body, they must match.

## Seeded API Tokens

By default, seeds create:

- Store token format: `store-token-<shop_code_lower>`
- POS token format: `pos-token-<shop_code_lower>-<pos_id_lower>`

Examples:

- `store-token-athlo`
- `pos-token-athlo-01`

## Headers

- Required:
  - `Content-Type: application/json`
  - `Authorization: Bearer <token>`
- Conditional:
  - `X-Pos-Id: <pos_id>` is required for store-scoped token and optional for POS-scoped token.

## Response Shape

### get-member

- `status` (bool)
- `member_found` (bool)
- `member_name` (string)
- `points_balance` (integer)
- `discount_total` (integer, cents)
- `scanned_vouchers[]`
- `discounts[]` (only positive discounts)
- `messages[]`

### finalize-order

- `status` (bool)
- `member_found` (bool)
- `member_name` (string)
- `points_collected` (integer)
- `current_points` (integer)
- `scanned_vouchers[]`
- `vouchers[]` (newly issued vouchers for printing/app)
- `messages[]` (receipt-ready lines)

`messages[]` for `finalize-order` is intended for receipt output and includes:

- `Staff total discount: EUR X.XX` (when staff discount is applied)
- `Used vouchers: N` + `Used voucher: <id> (<name>)` for each applied voucher (only when at least one voucher was applied)
- `Accrued points: N` (only when `N > 0`)
- `Accrued vouchers: N` (only when `N > 0`)

## Implemented Validation

- Missing or invalid bearer auth -> `401`.
- Unknown/inactive token -> `401`.
- Token scope mismatch -> `403`.
- Missing `X-Pos-Id` for store token -> `400`.
- `timestamp` format is `YYYY-MM-DD HH:MM:SS`.
- `transaction_value` and `change` are non-negative numbers.
- `vouchers` and `basket_items` are arrays when present.
- `tenders` can be provided optionally; if provided, it should be an array.

## Discount Rules

- Return only discounts with `discount > 0`.
- Stub currently writes discount lines to the first basket line.
- Staff discount (10%) is applied before voucher discounts.
- Voucher eligibility and application are evaluated after staff discount.

## Voucher Issuance Rules

- `finalize-order` is idempotent by `transaction_id`.
- For anonymous customer (no member identified and no member identifiers in payload), welcome voucher is issued only when:
  - `transaction_value >= welcome_min_purchase_amount`
- Default `welcome_min_purchase_amount` is `2500` (25.00).

## Validity Rules

Configured via `Loyalty -> Settings`:

- `standard_voucher_validity_days` (default `365`)
- `birthday_days_before` / `birthday_days_after` (default `7/7`)
- `welcome_min_purchase_amount` (default `2500`)

Voucher types:

- `WELCOME`: fixed days (`valid_from_offset_days=1`, `validity_days=14`)
- `BIRTHDAY`: birthday window (member-bound)
- `FIVE_OF_25`: standard fixed-days voucher

## Seeded Members (examples)

- `+353871234567` / card `3806868525360007` (David Brennan)
- `+353871234565` / card `3806868525360005` (Michael Doyle, staff)

## Integration Test Users (recommended)

For POS integration testing, prefer using these dedicated users. They are seeded
specifically for repeatable integration scenarios and already have active personal vouchers.

Each user has:
- 5 vouchers `2 off 15` (discount `200`, applicability threshold `1500`)
- 5 vouchers `5 off 25` (discount `500`, applicability threshold `2500`)
- 5 vouchers `11 off 50` (discount `1100`, applicability threshold `5000`)

Credentials:

1. `Integration Tester 01`:
   phone `+353879991001`, card `3806868525361001`
2. `Integration Tester 02`:
   phone `+353879991002`, card `3806868525361002`
3. `Integration Tester 03`:
   phone `+353879991003`, card `3806868525361003`
4. `Integration Tester 04`:
   phone `+353879991004`, card `3806868525361004`
5. `Integration Tester 05`:
   phone `+353879991005`, card `3806868525361005`

## Seeded Voucher Examples

User-bound:
- `96026705000030000007` (Standard, member-bound)
- `96026705000030000008` (Welcome, member-bound)

Anonymous:
- `96026705000030000011` (Welcome)
- `96026705000030000013` (Standard)

Birthday vouchers are always member-bound.

## Notes

- This is an integration stub with real persistence and idempotency behavior.
- Source of truth for contract remains [`loyalty.yaml`](./loyalty.yaml).
