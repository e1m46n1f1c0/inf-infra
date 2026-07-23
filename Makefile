.PHONY: setup up down logs

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