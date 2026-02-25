.PHONY: help setup build up down shell test logs

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## First-time setup (checks deps, creates .env, builds images)
	@bash scripts/setup.sh

build: ## Build sandbox and proxy images
	docker compose build

up: ## Start the sandbox
	docker compose up -d

down: ## Stop the sandbox
	docker compose down

shell: ## SSH into the sandbox
	ssh -p $${SAFE_AI_SSH_PORT:-2222} dev@localhost

test: ## Run smoke tests (containers must be running)
	@bash scripts/test.sh

logs: ## Tail proxy logs (see allowed/denied requests)
	docker compose logs -f proxy
