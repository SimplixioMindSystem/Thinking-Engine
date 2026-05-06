# ─────────────────────────────────────────────────────
# SimpliXio — Makefile
# Common development commands for the monorepo.
# ─────────────────────────────────────────────────────

.PHONY: help install lint test test-python test-swift security serve clean generate \
	autopilot-weekly autopilot-acq-daily autopilot-acq-weekly autopilot-all

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ── Setup ───────────────────────────────────────────

generate: ## Regenerate Xcode project (picks up local.yml for DEVELOPMENT_TEAM)
	cd CortexOSApp && LOCAL_YAML=1 xcodegen generate

install: ## Install Python deps into .venv
	python3 -m venv .venv
	.venv/bin/pip install --upgrade pip
	.venv/bin/pip install -r requirements.txt

# ── Linting & Security ─────────────────────────────

lint: ## Run ruff lint + format check
	.venv/bin/ruff check cortex_core/ tests/ scripts/
	.venv/bin/ruff format --check cortex_core/ tests/ scripts/

security: ## Run bandit security scan
	.venv/bin/bandit -r cortex_core/ -ll -q --skip B104

# ── Tests ───────────────────────────────────────────

test: test-python test-swift ## Run all tests

test-python: ## Run Python unit tests
	.venv/bin/python -m pytest tests/ -v --tb=short

test-swift: ## Build & test Swift package
	swift test

# ── Server ──────────────────────────────────────────

serve: ## Start the SimpliXio API server
	.venv/bin/python -m cortex_core.api.server

# ── Clean ───────────────────────────────────────────

clean: ## Remove build artifacts
	rm -rf .venv .build .pytest_cache __pycache__ .ruff_cache
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# ── Automation ─────────────────────────────────────

autopilot-weekly: ## Run strict weekly marketing automation pipeline
	cd cortexos_automation_scripts && python3 scripts/run_weekly_pipeline.py --strict-quality

autopilot-acq-daily: ## Run strict daily acquisition pipeline
	cd cortexos_automation_scripts && python3 scripts/run_acquisition_pipeline.py --mode daily --strict-quality

autopilot-acq-weekly: ## Run weekly acquisition review pipeline
	cd cortexos_automation_scripts && python3 scripts/run_acquisition_pipeline.py --mode weekly

autopilot-all: autopilot-weekly autopilot-acq-daily autopilot-acq-weekly ## Run all automation pipelines in safe order
