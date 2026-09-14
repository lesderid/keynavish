#!/bin/sh
#
# Builds and runs the offscreen render test (tests/render_test.d).
#
# Kept out of dub's build because it has its own main(); dub would link it into
# the application.
#
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$SCRIPT_DIR")

cd "$ROOT"

mkdir -p build

clang -c -fobjc-arc -fmodules -fmodules-cache-path=build/modulecache \
	-mmacosx-version-min=13.0 -o build/shim.o src/keynavish/platform/macos/shim.m

# Every source except main.d, which has the application's own entry point.
SOURCES=$(find src -name '*.d' ! -name 'main.d')

ldc2 -I=src -J=. -of=build/render_test \
	tests/render_test.d $SOURCES build/shim.o \
	-L-framework -LCocoa \
	-L-framework -LServiceManagement \
	-L-framework -LApplicationServices \
	-L-framework -LCarbon

exec ./build/render_test
