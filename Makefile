.PHONY: help setup up up-dev up-local up-all up-core up-tools up-realtime up-whatsapp up-wa up-s3 up-minio down logs ps restart backup setup-cron import-mysql import-postgres import-mongo

comma := ,
PROFILE_FLAGS := $(if $(PROFILES),$(foreach p,$(subst $(comma), ,$(PROFILES)),--profile $(p)))

help:
	@echo ""
	@echo "================================================================="
	@echo "   Infraestructura Orquestadora - Comandos Disponibles           "
	@echo "================================================================="
	@echo "Gestión del Stack:"
	@echo "  make setup                Copia .env.example a .env si no existe"
	@echo "  make up                   Inicia servicios (respeta COMPOSE_PROFILES en .env)"
	@echo "  make up PROFILES=s3,wa    Inicia servicios con perfiles específicos al vuelo"
	@echo "  make up-dev               Inicia stack completo de desarrollo (perfil 'dev')"
	@echo "  make up-local             Inicia stack local completo (perfil 'local')"
	@echo "  make up-realtime          Inicia núcleo + Centrifugo (WebSockets / Tiempo Real)"
	@echo "  make up-whatsapp          Inicia núcleo + Evolution API (WhatsApp API)"
	@echo "  make up-s3                Inicia núcleo + MinIO S3 (Almacenamiento de Objetos)"
	@echo "  make up-tools             Inicia herramientas (DbGate, Mailpit, RedisInsight, Bull-Board)"
	@echo "  make up-core              Inicia SOLO el núcleo (Traefik, MySQL, Postgres, Mongo, Redis)"
	@echo "  make up-all               Inicia TODOS los servicios y perfiles"
	@echo "  make down                 Detiene y remueve los contenedores"
	@echo "  make restart              Reinicia los contenedores"
	@echo "  make ps                   Muestra el estado de los contenedores"
	@echo "  make logs                 Sigue los logs de los contenedores"
	@echo ""
	@echo "Bases de Datos & Backups:"
	@echo "  make import-mysql <db> <file.sql[.gz|.zip]>"
	@echo "  make import-postgres <db> <file.sql[.gz|.zip]>"
	@echo "  make import-mongo <db> <file[.json|.gz|.zip|.archive]> [<col_name>]"
	@echo "  make backup [TYPE=hourly|daily|weekly|monthly]"
	@echo "  make setup-cron           Registra los cron jobs de respaldo automatizado"
	@echo "================================================================="
	@echo ""

setup:
	@echo "Configuring client infrastructure..."
	@[ -f .env ] && echo "The .env file already exists." || cp .env.example .env

fetch-certs:
	@echo "Fetching Root CA from global-step-ca..."
	@mkdir -p certs
	@docker cp global-step-ca:/home/step/certs/root_ca.crt ./certs/root_ca.crt 2>/dev/null || echo "Warning: Could not fetch root_ca.crt from global-step-ca"

up: fetch-certs
	docker compose $(PROFILE_FLAGS) up -d

up-dev: fetch-certs
	docker compose --profile dev up -d

up-local: fetch-certs
	docker compose --profile local up -d

up-realtime: fetch-certs
	docker compose --profile realtime up -d

up-whatsapp: fetch-certs
	docker compose --profile whatsapp up -d

up-wa: fetch-certs
	docker compose --profile whatsapp up -d

up-s3: fetch-certs
	docker compose --profile s3 up -d

up-minio: fetch-certs
	docker compose --profile s3 up -d

up-tools: fetch-certs
	docker compose --profile tools up -d

up-core: fetch-certs
	COMPOSE_PROFILES="" docker compose up -d

up-all: fetch-certs
	docker compose --profile local --profile dev --profile tools --profile s3 --profile minio --profile whatsapp --profile evolution --profile realtime --profile centrifugo --profile redisinsight --profile queues --profile bullboard up -d

down:
	docker compose down

restart:
	docker compose restart

ps:
	docker compose ps

logs:
	docker compose logs -f

# Capturar argumentos posicionales para comandos de importación
SUPPORTED_IMPORTS := import-mysql import-postgres import-mongo
ifneq ($(filter $(firstword $(MAKECMDGOALS)),$(SUPPORTED_IMPORTS)),)
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(RUN_ARGS):;@:)
endif

import-mysql:
	@bash scripts/import-db.sh mysql $(word 2,$(MAKECMDGOALS)) $(word 3,$(MAKECMDGOALS))

import-postgres:
	@bash scripts/import-db.sh postgres $(word 2,$(MAKECMDGOALS)) $(word 3,$(MAKECMDGOALS))

import-mongo:
	@bash scripts/import-db.sh mongo $(word 2,$(MAKECMDGOALS)) $(word 3,$(MAKECMDGOALS)) $(word 4,$(MAKECMDGOALS))

backup:
	@bash scripts/backup-db.sh $(TYPE)

setup-cron:
	@echo "Configuring cron tasks for database backups..."
	@CURR_DIR=$$(pwd) ; \
	(crontab -l 2>/dev/null | grep -v "$$CURR_DIR" ; \
	echo "# Database Backups ($$CURR_DIR)" ; \
	echo "0 * * * * cd $$CURR_DIR && make backup TYPE=hourly >> /tmp/cron-backup.log 2>&1" ; \
	echo "0 2 * * * cd $$CURR_DIR && make backup TYPE=daily >> /tmp/cron-backup.log 2>&1" ; \
	echo "0 2 * * 0 cd $$CURR_DIR && make backup TYPE=weekly >> /tmp/cron-backup.log 2>&1" ; \
	echo "0 2 1 * * cd $$CURR_DIR && make backup TYPE=monthly >> /tmp/cron-backup.log 2>&1" \
	) | crontab -
	@echo "Cron tasks successfully registered."