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