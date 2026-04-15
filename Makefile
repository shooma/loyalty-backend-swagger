HOST ?= 127.0.0.1
PORT ?= 8080

.PHONY: swagger-local

swagger-local:
	HOST="$(HOST)" PORT="$(PORT)" ./scripts/run-swagger-local.sh
