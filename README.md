# Loyalty Backend Swagger

OpenAPI specification and Swagger UI for the Loyalty Backend API.

## Available environments

The Swagger `Servers` dropdown includes:

- `https://erp.polonez.ie` - Production
- `https://odoo-stage.polonez.dev` - Staging
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
