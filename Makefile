#!/usr/bin/make -f

BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
COMMIT := $(shell git log -1 --format='%H')
GO_VERSION := 1.26

# don't override user values
ifeq (,$(VERSION))
  VERSION := $(shell git describe --tags)
  # if VERSION is empty, then populate it with branch's name and raw commit hash
  ifeq (,$(VERSION))
    VERSION := $(BRANCH)-$(COMMIT)
  endif
endif

PACKAGES_SIMTEST=$(shell go list ./... | grep '/simulation')
LEDGER_ENABLED ?= true
SDK_PACK := $(shell go list -m github.com/cosmos/cosmos-sdk | sed  's/ /\@/g')
TM_VERSION := $(shell go list -m github.com/cometbft/cometbft | sed 's:.* ::') # grab everything after the space in "github.com/cometbft/cometbft v0.37.0"
BUILDDIR ?= $(CURDIR)/build
DOCKER := $(shell which docker)
DOCKER_BUF := $(DOCKER) run --rm -v $(CURDIR):/workspace --workdir /workspace bufbuild/buf:1.7.0

export GO111MODULE = on

# process build tags

build_tags = netgo
ifeq ($(LEDGER_ENABLED),true)
  ifeq ($(OS),Windows_NT)
    GCCEXE = $(shell where gcc.exe 2> NUL)
    ifeq ($(GCCEXE),)
      $(error gcc.exe not installed for ledger support, please install or set LEDGER_ENABLED=false)
    else
      build_tags += ledger
    endif
  else
    UNAME_S = $(shell uname -s)
    ifeq ($(UNAME_S),OpenBSD)
      $(warning OpenBSD detected, disabling ledger support (https://github.com/cosmos/cosmos-sdk/issues/1988))
    else
      GCC = $(shell command -v gcc 2> /dev/null)
      ifeq ($(GCC),)
        $(error gcc not installed for ledger support, please install or set LEDGER_ENABLED=false)
      else
        build_tags += ledger
      endif
    endif
  endif
endif

ifeq (cleveldb,$(findstring cleveldb,$(medasdigital_BUILD_OPTIONS)))
  build_tags += gcc cleveldb
endif
build_tags += $(BUILD_TAGS)
build_tags := $(strip $(build_tags))

whitespace :=
whitespace += $(whitespace)
comma := ,
build_tags_comma_sep := $(subst $(whitespace),$(comma),$(build_tags))

# process linker flags

ldflags = -X github.com/cosmos/cosmos-sdk/version.Name=medasdigital \
		  -X github.com/cosmos/cosmos-sdk/version.AppName=medasdigitald \
		  -X github.com/cosmos/cosmos-sdk/version.Version=$(VERSION) \
		  -X github.com/cosmos/cosmos-sdk/version.Commit=$(COMMIT) \
		  -X "github.com/cosmos/cosmos-sdk/version.BuildTags=$(build_tags_comma_sep)" \
			-X github.com/tendermint/tendermint/version.TMCoreSemVer=$(TM_VERSION)

ifeq (cleveldb,$(findstring cleveldb,$(medasdigital_BUILD_OPTIONS)))
  ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=cleveldb
endif
ifeq (,$(findstring nostrip,$(medasdigital_BUILD_OPTIONS)))
  ldflags += -w -s
endif
ifeq ($(LINK_STATICALLY),true)
        ldflags += -linkmode=external -extldflags "-Wl,-z,muldefs -static"
endif
ldflags += $(LDFLAGS)
ldflags := $(strip $(ldflags))

BUILD_FLAGS := -tags "$(build_tags)" -ldflags '$(ldflags)'
# check for nostrip option
ifeq (,$(findstring nostrip,$(medasdigital_BUILD_OPTIONS)))
  BUILD_FLAGS += -trimpath
endif

#$(info $$BUILD_FLAGS is [$(BUILD_FLAGS)])


all: check-go-version install

install: check-go-version go.sum
	go install -mod=readonly $(BUILD_FLAGS) ./cmd/medasdigitald

build: check-go-version
	go build $(BUILD_FLAGS) -o bin/medasdigitald ./cmd/medasdigitald

BUILD_TARGETS := build install

# Binaries for scripts/upgrade-test.sh:
#   build/old/medasdigitald  from OLD_REF (default 050907c = mainnet v1.0.1 code),
#                            built in a temporary worktree with that commit's Makefile
#   build/new/medasdigitald  from the current checkout
OLD_REF ?= 050907c
UPGRADE_OLD_SRC := $(BUILDDIR)/old-src

build-upgrade-binaries: build
	@echo "Building old binary from $(OLD_REF)"
	@git worktree remove --force $(UPGRADE_OLD_SRC) 2>/dev/null || true
	@git worktree add --detach $(UPGRADE_OLD_SRC) $(OLD_REF)
	@GOTOOLCHAIN=go1.22.11 $(MAKE) -C $(UPGRADE_OLD_SRC) build
	@mkdir -p $(BUILDDIR)/old $(BUILDDIR)/new
	@cp $(UPGRADE_OLD_SRC)/bin/medasdigitald $(BUILDDIR)/old/medasdigitald
	@git worktree remove --force $(UPGRADE_OLD_SRC)
	@cp bin/medasdigitald $(BUILDDIR)/new/medasdigitald

.PHONY: build-upgrade-binaries

# Reproducible static release binary (see Dockerfile). Refuses to build from a
# dirty tree, because VERSION/COMMIT would not describe the sources.
build-release:
	@test -z "$$(git status --porcelain)" || { echo "working tree not clean"; exit 1; }
	DOCKER_BUILDKIT=1 $(DOCKER) build --target export --output type=local,dest=$(BUILDDIR)/release \
		--build-arg VERSION=$(VERSION) --build-arg COMMIT=$(COMMIT) .
	cd $(BUILDDIR)/release && sha256sum medasdigitald | tee medasdigitald.sha256

.PHONY: build-release

build-reproducible-all: build-reproducible-amd64 build-reproducible-arm64

build-reproducible-amd64:
	ARCH=x86_64 PLATFORM=linux/amd64 $(MAKE) build-reproducible-generic

build-reproducible-arm64:
	ARCH=aarch64 PLATFORM=linux/arm64 $(MAKE) build-reproducible-generic

build-reproducible-generic: go.sum
	$(DOCKER) rm $(subst /,-,latest-build-$(PLATFORM)) || true
	DOCKER_BUILDKIT=1 $(DOCKER) build -t latest-build-$(PLATFORM) \
		--build-arg ARCH=$(ARCH) \
		--build-arg GO_VERSION=$(GO_VERSION) \
		--build-arg PLATFORM=$(PLATFORM) \
		--build-arg VERSION="$(VERSION)" \
		-f Dockerfile .
	$(DOCKER) create -ti --name $(subst /,-,latest-build-$(PLATFORM)) latest-build-$(PLATFORM) medasdigitald
	$(DOCKER) cp -a $(subst /,-,latest-build-$(PLATFORM)):/usr/local/bin/medasdigitald medasdigitald_$(subst /,_,$(PLATFORM))
	sha256sum medasdigitald_$(subst /,_,$(PLATFORM)) >> ./medasdigitald_sha256.txt

# Add check to make sure we are using the proper Go version before proceeding with anything
check-go-version:
	@go_actual=$$(go version | awk '{print $$3}' | cut -c3-); \
	go_major_minor=$$(echo $$go_actual | cut -d. -f1,2); \
	if [ "$$go_major_minor" != "$(GO_VERSION)" ]; then \
		echo "\033[0;31mERROR:\033[0m Go version $(GO_VERSION).x is required for compiling medasdigitald."; \
		echo "It looks like you are using: $$(go version)"; \
		echo "There are potential consensus-breaking changes that can occur when running binaries compiled with different versions of Go."; \
		echo "Please download Go version $(GO_VERSION).x and retry. Thank you!"; \
		exit 1; \
	fi

###############################################################################
###                                Protobuf                                 ###
###############################################################################

# Proto generation runs buf directly with the plugin versions pinned in go.mod
# (see tools/tools.go). No Ignite and no Docker needed. The tools are installed
# into build/tools so they do not collide with anything on the PATH.
PROTO_TOOLS_DIR := $(BUILDDIR)/tools
PROTO_TOOLS := \
	github.com/bufbuild/buf/cmd/buf \
	github.com/cosmos/cosmos-proto/cmd/protoc-gen-go-pulsar \
	github.com/cosmos/gogoproto/protoc-gen-gocosmos \
	github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway \
	google.golang.org/grpc/cmd/protoc-gen-go-grpc

proto-tools:
	@echo "Installing pinned proto tools into $(PROTO_TOOLS_DIR)"
	@GOBIN=$(PROTO_TOOLS_DIR) go install $(PROTO_TOOLS)

# gogo output lands under <go_package>/ (medasdigital/x/...), so it is generated
# into a temp dir and only the x/ tree is copied back, like Ignite does.
# module/module.proto has no x/ go_package; its gogo output is discarded
# (the pulsar variant under api/ is the one used by depinject).
proto-gen: proto-tools
	@echo "Generating Protobuf files"
	@set -e; tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	cd proto; \
	PATH=$(PROTO_TOOLS_DIR):$$PATH buf generate --template buf.gen.gogo.yaml --output $$tmp; \
	PATH=$(PROTO_TOOLS_DIR):$$PATH buf generate --template buf.gen.pulsar.yaml --output $(CURDIR); \
	cp -r $$tmp/medasdigital/x/. $(CURDIR)/x/

# Fails if the committed generated files differ from a fresh generation.
proto-check: proto-gen
	@git diff --exit-code -- '*.pb.go' '*.pb.gw.go' '*.pulsar.go' \
		&& echo "Generated protobuf files are up to date"

.PHONY: proto-tools proto-gen proto-check

docs:
	@echo
	@echo "=========== Generate Message ============"
	@echo
	./scripts/protoc-swagger-gen.sh

	statik -src=client/docs/static -dest=client/docs -f -m
	@if [ -n "$(git status --porcelain)" ]; then \
        echo "\033[91mSwagger docs are out of sync!!!\033[0m";\
        exit 1;\
    else \
        echo "\033[92mSwagger docs are in sync\033[0m";\
    fi
	@echo
	@echo "=========== Generate Complete ============"
	@echo
.PHONY: docs
