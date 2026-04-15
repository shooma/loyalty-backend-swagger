HOST ?= 127.0.0.1
PORT ?= 8080

.PHONY: swagger-local swagger-local-start swagger-local-stop swagger-local-status swagger-local-logs swagger-local-restart

swagger-local:
	HOST="$(HOST)" PORT="$(PORT)" ./scripts/run-swagger-local.sh

swagger-local-start:
	HOST="$(HOST)" PORT="$(PORT)" ./scripts/swagger-local-daemon.sh start

swagger-local-stop:
	./scripts/swagger-local-daemon.sh stop

swagger-local-status:
	./scripts/swagger-local-daemon.sh status

swagger-local-logs:
	./scripts/swagger-local-daemon.sh logs

swagger-local-restart:
	HOST="$(HOST)" PORT="$(PORT)" ./scripts/swagger-local-daemon.sh restart
