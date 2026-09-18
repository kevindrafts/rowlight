#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/clang .build/tmp
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang"
export TMPDIR="$PWD/.build/tmp"
command="$1"
shift
exec swift "$command" --disable-sandbox --cache-path "$PWD/.build/cache" "$@"
