.PHONY: pdf html docker-build docker-pdf docker-html docker recipe-pdf all catalog catalog-check label-test thumbnail-queue thumbnail-validate sim-build sim-launch phone-build phone-install phone-launch phone-deploy test

DOCKER_PLATFORM ?= linux/amd64
DOCKER_IMAGE ?= cookbook-latex

all: pdf html

pdf:
	pdflatex Cookbook.tex

html:
	./run_html.py --index Cookbook.tex > Cookbook.html

docker-build:
	docker build --platform "$(DOCKER_PLATFORM)" --tag "$(DOCKER_IMAGE)" .

docker-pdf: docker-build
	docker run --rm --platform "$(DOCKER_PLATFORM)" --volume "$(PWD):/work" --workdir /work \
		--user "$(shell id -u):$(shell id -g)" --env HOME=/tmp "$(DOCKER_IMAGE)" \
		latexmk -pdf -interaction=nonstopmode -halt-on-error Cookbook.tex

docker-html:
	docker run --rm --volume "$(PWD):/work" --workdir /work python:3.13-slim \
		python3 run_html.py --index Cookbook.tex > Cookbook.html

docker: docker-pdf docker-html

RECIPE ?=

recipe-pdf:
	@test -n "$(RECIPE)" || { echo "Usage: make recipe-pdf RECIPE=<recipe-id-or-source-slug>" >&2; exit 2; }
	python3 scripts/recipe_pdf.py prepare "$(RECIPE)"
	$(MAKE) docker-build
	docker run --rm --platform "$(DOCKER_PLATFORM)" --volume "$(PWD):/work" --workdir /work \
		--user "$(shell id -u):$(shell id -g)" --env HOME=/tmp "$(DOCKER_IMAGE)" \
		latexmk -pdf -interaction=nonstopmode -halt-on-error -outdir=build/recipe-pdf \
		build/recipe-pdf/$(RECIPE)-preview.tex
	python3 scripts/recipe_pdf.py check "$(RECIPE)"

IOS_PROJECT := ios/Cookbook.xcodeproj
IOS_SCHEME := Cookbook
IOS_APP := Cookbook
IOS_BUNDLE_ID := com.cseibert.Cookbook
IOS_DERIVED_DATA := build/ios
SIM_DEVICE_NAME ?= iPhone 17 Pro
SIM_DESTINATION ?= platform=iOS Simulator,name=$(SIM_DEVICE_NAME)
GENERIC_SIM_DESTINATION := generic/platform=iOS Simulator
DEVICE_ID ?= 00008150-000E41422E40401C
DEVELOPMENT_TEAM ?= 96NAC4VTEN

catalog:
	python3 scripts/generate_mobile_catalog.py

catalog-check:
	python3 scripts/generate_mobile_catalog.py --check

label-test: catalog-check
	@set -eu; binary=$$(mktemp /tmp/cookbook-label-tests.XXXXXX); trap 'rm -f "$$binary"' EXIT; \
	  CLANG_MODULE_CACHE_PATH=/private/tmp/cookbook-label-module-cache swiftc ios/Cookbook/Catalog.swift tests/RecipeLabelTests.swift -o "$$binary"; \
	  "$$binary"

REMAINING_PERCENT ?=
QUOTA_CHECKED_AT ?=

thumbnail-queue:
	python3 scripts/recipe_thumbnails.py queue $(if $(REMAINING_PERCENT),--remaining-percent $(REMAINING_PERCENT),) $(if $(QUOTA_CHECKED_AT),--quota-checked-at '$(QUOTA_CHECKED_AT)',)

thumbnail-validate:
	python3 scripts/recipe_thumbnails.py validate

sim-build: catalog-check
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -configuration Debug \
	  -destination '$(GENERIC_SIM_DESTINATION)' -derivedDataPath $(IOS_DERIVED_DATA) \
	  CODE_SIGNING_ALLOWED=NO build

sim-launch: sim-build
	@set -eu; \
	UDID=$$(xcrun simctl list devices available | awk -F '[()]' -v name="$(SIM_DEVICE_NAME)" '{ display=$$1; sub(/^[[:space:]]+/, "", display); sub(/[[:space:]]+$$/, "", display); if (display == name && $$0 !~ /unavailable/) { print $$2; exit } }'); \
	if [ -z "$$UDID" ]; then echo "No available simulator named $(SIM_DEVICE_NAME)."; xcrun simctl list devices available; exit 1; fi; \
	xcrun simctl boot "$$UDID" >/dev/null 2>&1 || true; xcrun simctl bootstatus "$$UDID" -b; \
	open -a Simulator --args -CurrentDeviceUDID "$$UDID"; \
	xcrun simctl install "$$UDID" "$(IOS_DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(IOS_APP).app"; \
	xcrun simctl launch "$$UDID" $(IOS_BUNDLE_ID)

phone-build: catalog-check
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -configuration Debug \
	  -destination 'platform=iOS,id=$(DEVICE_ID)' -derivedDataPath $(IOS_DERIVED_DATA) \
	  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
	  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

phone-install:
	xcrun devicectl device install app --device $(DEVICE_ID) "$(IOS_DERIVED_DATA)/Build/Products/Debug-iphoneos/$(IOS_APP).app"

phone-launch:
	xcrun devicectl device process launch --device $(DEVICE_ID) --terminate-existing $(IOS_BUNDLE_ID)

phone-deploy: phone-build phone-install phone-launch

test: catalog-check label-test
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -configuration Debug \
	  -destination '$(GENERIC_SIM_DESTINATION)' -derivedDataPath $(IOS_DERIVED_DATA) \
	  CODE_SIGNING_ALLOWED=NO test
