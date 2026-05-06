SHELL := /bin/bash

APP_NAME := Sussurro
APP_BUNDLE := $(APP_NAME).app
DIST_APP := dist/$(APP_BUNDLE)
SYSTEM_APP := /Applications/$(APP_BUNDLE)
USER_APP := $(HOME)/Applications/$(APP_BUNDLE)

.DEFAULT_GOAL := help

.PHONY: help build install remove clean

help:
	@printf 'Usage: make <target>\n\n'
	@printf 'Targets:\n'
	@printf '  build    Build %s into dist/\n' '$(APP_BUNDLE)'
	@printf '  install  Build and install %s into /Applications or ~/Applications\n' '$(APP_BUNDLE)'
	@printf '  remove   Quit and remove installed/built %s bundles; keep app data\n' '$(APP_BUNDLE)'
	@printf '  clean    Remove local build artifacts\n'

build:
	@scripts/build-app.sh

install:
	@scripts/install-app.sh

remove:
	@osascript -e 'tell application "$(APP_NAME)" to quit' >/dev/null 2>&1 || true
	@removed=0; \
	failed=0; \
	for app in '$(SYSTEM_APP)' '$(USER_APP)' '$(DIST_APP)'; do \
		if [[ -e "$$app" ]]; then \
			if rm -rf "$$app"; then \
				printf 'Removed: %s\n' "$$app"; \
				removed=1; \
			else \
				printf 'Could not remove: %s\n' "$$app" >&2; \
				failed=1; \
			fi; \
		fi; \
	done; \
	if [[ "$$failed" -ne 0 ]]; then \
		exit 1; \
	fi; \
	if [[ "$$removed" -eq 0 ]]; then \
		printf 'No Sussurro app bundle found in /Applications, ~/Applications, or dist/.\n'; \
	fi; \
	printf 'Kept app data: %s\n' '$(HOME)/Library/Application Support/Sussurro'; \
	printf 'Kept logs: %s\n' '$(HOME)/Library/Logs/Sussurro'

clean:
	@rm -rf .build dist
	@printf 'Removed local build artifacts.\n'
