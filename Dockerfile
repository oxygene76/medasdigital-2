# Reproducible, statically linked medasdigitald release build.
#
#   make build-release   ->  build/release/medasdigitald + .sha256
#
# Everything that influences the binary is pinned: the Go image (by digest),
# the Alpine packages (exact versions; the build fails if one is no longer
# available instead of silently using another), libwasmvm_muslc (sha256 of
# the official release) and the Go modules (go.sum). The binary links
# libwasmvm statically, so it does not use /lib/libwasmvm.x86_64.so of the
# host, which the running v1.0.1 binary still needs.

# golang:1.26.8-alpine3.24
ARG GO_IMAGE=golang:1.26.8-alpine3.24@sha256:8ac98ca534ac3f51e1f420a1dd2c15e74c75cfa0f23f3ad27eb5d7236c349a0c

FROM ${GO_IMAGE} AS builder

ARG WASMVM_VERSION=v2.2.9
ARG WASMVM_MUSLC_SHA256=56e7c590fe11a6a51381c80c2710f71af1244acfb8cd1d5839d638313b7bd401
ARG VERSION
ARG COMMIT

RUN apk add --no-cache \
      build-base=0.5-r4 \
      gcc=15.2.0-r5 \
      musl-dev=1.2.6-r2 \
      binutils=2.45.1-r1 \
      make=4.4.1-r4 \
      linux-headers=7.0.0-r1

ADD https://github.com/CosmWasm/wasmvm/releases/download/${WASMVM_VERSION}/libwasmvm_muslc.x86_64.a /lib/libwasmvm_muslc.x86_64.a
RUN echo "${WASMVM_MUSLC_SHA256}  /lib/libwasmvm_muslc.x86_64.a" | sha256sum -c -

WORKDIR /src
COPY go.mod go.sum ./
# The static library must match the wasmvm version in go.mod.
RUN GOTOOLCHAIN=local go mod download && GOTOOLCHAIN=local go mod verify \
 && test "$(GOTOOLCHAIN=local go list -m -f '{{.Version}}' github.com/CosmWasm/wasmvm/v2)" = "${WASMVM_VERSION}"

COPY . .
RUN test -n "${VERSION}" && test -n "${COMMIT}" \
 && GOTOOLCHAIN=local LEDGER_ENABLED=true LINK_STATICALLY=true BUILD_TAGS=muslc \
    make build VERSION="${VERSION}" COMMIT="${COMMIT}" \
 && ! readelf -d bin/medasdigitald 2>/dev/null | grep -q NEEDED \
 && bin/medasdigitald version --long --home /tmp/h | grep -E "^(version|commit|build_tags|go):" \
 && bin/medasdigitald query wasm libwasmvm-version --home /tmp/h | grep -qx "${WASMVM_VERSION#v}" \
 && sha256sum bin/medasdigitald

FROM scratch AS export
COPY --from=builder /src/bin/medasdigitald /medasdigitald
