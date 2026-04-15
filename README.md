# Loyalty Backend Swagger

OpenAPI specification and Swagger UI for the Loyalty Backend API.

Public Swagger UI:
- `https://shooma.github.io/loyalty-backend-swagger/`

## Integration docs

- API contract: [`loyalty.yaml`](./loyalty.yaml)
- Stub/backend behavior notes for POS integrators: [`STUB_API.md`](./STUB_API.md)

## Integration test credentials (wiki quick reference)

Use these dedicated users first for manual and automated integration runs:

1. `Integration Tester 01`: phone `+353879991001`, card `3806868525361001`
2. `Integration Tester 02`: phone `+353879991002`, card `3806868525361002`
3. `Integration Tester 03`: phone `+353879991003`, card `3806868525361003`
4. `Integration Tester 04`: phone `+353879991004`, card `3806868525361004`
5. `Integration Tester 05`: phone `+353879991005`, card `3806868525361005`

Each test user is pre-seeded with 15 active personal vouchers:
- 5x `2 off 15`
- 5x `5 off 25`
- 5x `11 off 50`

## Available environments

The Swagger `Servers` dropdown includes:

- `https://odoo-stage.polonez.dev` - Staging
- `https://erp.polonez.ie` - Production
- `http://localhost:8069` - Local Odoo

## Run Swagger locally

Swagger UI must be served over HTTP. Opening `index.html` directly from the filesystem may fail in the browser because the spec file is loaded with a relative HTTP request.

From the repository root:

```bash
make swagger-local
```

Then open:

```text
http://localhost:8080
```

Optional overrides:

```bash
HOST=0.0.0.0 PORT=8081 make swagger-local
```

## Alternative command

If you do not want to use `make`, you can run the helper script directly:

```bash
./scripts/run-swagger-local.sh
```

## Run Swagger locally in detached mode

Start server in background:

```bash
make swagger-local-start
```

Check status:

```bash
make swagger-local-status
```

Stop server:

```bash
make swagger-local-stop
```

Follow logs:

```bash
make swagger-local-logs
```

The detached mode writes:

- PID: `.swagger-local.pid`
- Logs: `.swagger-local.log`

You can also override host/port:

```bash
HOST=0.0.0.0 PORT=8081 make swagger-local-start
```
