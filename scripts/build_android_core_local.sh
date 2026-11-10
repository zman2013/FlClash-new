#!/bin/bash
# Reuse the local toolchain and Go cache. Builds only the connected arm64 target.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
ndk_dir="${ANDROID_NDK_HOME:-/opt/homebrew/share/android-commandlinetools/ndk/28.0.13004108}"
# The parent repository pins the reviewed observer commit in this submodule.
if ! git -C "$repo_dir/core/Clash.Meta" grep -q DefaultTrafficNotify HEAD -- tunnel/statistic/patch.go; then
  echo 'Pinned core observer is missing; run git submodule update --init core/Clash.Meta.' >&2
  exit 1
fi
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/flclash-core.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
cd "$repo_dir/core"
GOPROXY="${GOPROXY:-off}" GOSUMDB="${GOSUMDB:-off}" \
CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
CC="$ndk_dir/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android21-clang" \
go build -tags=with_gvisor -ldflags='-w -s' -buildmode=c-shared -o "$build_dir/libclash.so" .
mkdir -p "$repo_dir/libclash/android/arm64-v8a" "$repo_dir/libclash/android/includes/arm64-v8a"
cp "$build_dir/libclash.so" "$repo_dir/libclash/android/arm64-v8a/libclash.so"
cp "$build_dir/libclash.h" "$repo_dir/libclash/android/includes/arm64-v8a/libclash.h"
echo 'Built Android arm64 core with proxy payload accounting.'
