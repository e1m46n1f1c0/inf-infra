.PHONY: setup up down logs

help:
	@echo ""

setup:
	@echo "Configuring client infrastructure..."
	@[ -f .env ] && echo "The .env file already exists." || cp .env.example .env

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

# Capturar argumentos posicionales para los comandos de importación
ifeq ($(firstword $(MAKECMDGOALS)),import-mysql)
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(RUN_ARGS):;@:)
endif

ifeq ($(firstword $(MAKECMDGOALS)),import-mongo)
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(RUN_ARGS):;@:)
endif

import-mysql:
	@bash scripts/import-db.sh mysql $(word 2,$(MAKECMDGOALS)) $(word 3,$(MAKECMDGOALS))

import-mongo:
	@bash scripts/import-db.sh mongo $(word 2,$(MAKECMDGOALS)) $(word 3,$(MAKECMDGOALS)) $(word 4,$(MAKECMDGOALS))

backup:
	@bash scripts/backup-db.sh $(TYPE)

setup-cron:
	@echo "Configuring cron tasks for database backups..."
	@CURR_DIR=$$(pwd) ; \
	(crontab -l 2>/dev/null | grep -v "$$CURR_DIR/scripts/backup-db.sh" ; \
	echo "# Database Backups ($$CURR_DIR)" ; \
	echo "0 * * * * cd $$CURR_DIR && make backup TYPE=hourly >> /tmp/cron-backup.log 2>&1" ; \
	echo "0 2 * * * cd $$CURR_DIR && make backup TYPE=daily >> /tmp/cron-backup.log 2>&1" ; \
	echo "0 2 * * 0 cd $$CURR_DIR && make backup TYPE=weekly >> /tmp/cron-backup.log 2>&1" ; \
	echo "0 2 1 * * cd $$CURR_DIR && make backup TYPE=monthly >> /tmp/cron-backup.log 2>&1" \
	) | crontab -
	@echo "Cron tasks successfully registered."