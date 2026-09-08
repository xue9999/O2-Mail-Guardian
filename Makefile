GO ?= go
GOVULNCHECK_VERSION ?= v1.7.0
VERSION ?= $(shell tr -d '[:space:]' < VERSION)
LDFLAGS ?= -s -w -X main.version=$(VERSION)

.PHONY: build build-swift test test-swift vuln package check

build:
	mkdir -p bin
	$(GO) build -trimpath -ldflags "$(LDFLAGS)" -o bin/guardian ./cmd/guardian

test:
	$(GO) test ./...

build-swift:
	swift build --package-path macos

test-swift:
	bash scripts/test-swift.sh

vuln:
	$(GO) run golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION) ./...

package:
	bash scripts/package-release.sh

check:
	$(GO) test -race ./...
	$(GO) vet ./...
	$(MAKE) vuln GO="$(GO)"
	bash scripts/test-swift.sh
	bash scripts/test-gui-mock-onboarding.sh
	bash scripts/test-installer-wrapper.sh
	bash scripts/test-installer-rollback.sh
	bash scripts/test-deploy-config.sh
	bash scripts/test-release-package.sh
	bash -n Install.command Guardian.command Uruchom-teraz.command Sprawdz-stan.command scripts/*.command scripts/*.sh
