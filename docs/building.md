# Building medasdigitald from source

Operators normally use the release binaries from
[GitHub Releases](https://github.com/oxygene76/medasdigital-2/releases). This page
explains how to build a release yourself and how to check that your build
matches the published binary.

**Always build from a release tag, never from `main`.** `main` may contain
changes that are not part of the software running on the network. A binary
that differs from the network's version can stop at a consensus mismatch.

## Go version per release

The Go version is part of the release and must match exactly in major and minor
version. `make build` refuses to run with a different Go version.

| Release | Go | libwasmvm | Linking |
|---|---|---|---|
| v1.0.1 | 1.22.11 | 2.1.2 | dynamic (`libwasmvm.x86_64.so` must be installed) |
| v2.0.0 (upcoming) | 1.26.8 | 2.2.9 | static (musl), built in Docker |

## Requirements

- Linux x86_64 with `git`, `make` and a C compiler (`gcc`). CosmWasm needs CGO;
  without a C compiler the build fails.
- For v1.0.1: Go 1.22.11 and libwasmvm 2.1.2 (see [README](../README.md#manual-setup)).
- For v2.0.0 and later: Docker with buildx. The Go toolchain and all other build
  dependencies come from the pinned build image.

## v2.0.0 and later: reproducible release build

From v2.0.0 on the release binary is built in Docker. Everything that
influences the result is pinned:
- the Go image by digest,
- the Alpine packages by exact version,
- `libwasmvm_muslc` by the SHA-256 of the official wasmvm release,
- the Go modules by `go.sum`.

The same tag therefore produces the same binary on every machine.

```sh
git clone https://github.com/oxygene76/medasdigital-2.git
cd medasdigital-2
git checkout v2.0.0
make build-release VERSION=v2.0.0
cat build/release/medasdigitald.sha256
```

- Compare the checksum with the one in the GitHub release. They must be
  identical.
- `VERSION` must be the tag name, because it is embedded in the binary.
- The build refuses to run on a working tree with local changes.

Checks of the result:

```sh
ldd build/release/medasdigitald                          # not a dynamic executable
build/release/medasdigitald version --long | grep -E '^(version|commit|go|build_tags):'
build/release/medasdigitald query wasm libwasmvm-version # 2.2.9
```

## v1.0.1

```sh
git checkout v1.0.1
make build VERSION=v1.0.1          # -> bin/medasdigitald, tags "netgo ledger"
bin/medasdigitald version          # v1.0.1
```

The published v1.0.1 binary (SHA-256 `676a9d2f4f0648994a7da8b30ab4fbbd69018bd82c23f1c077e2b01044871a68`)
cannot be reproduced byte-for-byte:
- It was built before the reproducible build existed.
- It embeds the commit `a77373b` of the working tree it was built from. The
  source is identical to tag `v1.0.1`, see the tag message.

Instead, compare the dependencies. `version --long` of your build and of the
release binary must list exactly the same `build_deps` (179 modules), the same
Go version and the same build tags:

```sh
diff <(bin/medasdigitald version --long | grep '^- ') \
     <(./medasdigitald-v1.0.1-release version --long | grep '^- ') && echo "build_deps identical"
```

For running a node, use the published v1.0.1 binary.
