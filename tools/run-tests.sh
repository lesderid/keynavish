#!/bin/sh
#
# Builds and runs the test suites in tests/.
#
# They are kept out of the dub build because each has its own main(); dub would
# link them into the application. None of them need Accessibility permission,
# so they run unattended and in CI.
#
# Usage: tools/run-tests.sh [test-name ...]   (default: all)
#
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$SCRIPT_DIR")

cd "$ROOT"
mkdir -p build

TESTS="${*:-config keys render}"

case "$(uname -s)" in
Darwin)
	clang -c -fobjc-arc -fmodules -fmodules-cache-path=build/modulecache \
		-mmacosx-version-min=13.0 -o build/shim.o \
		src/keynavish/platform/macos/shim.m

	EXTRA="build/shim.o
		-L-framework -LCocoa
		-L-framework -LServiceManagement
		-L-framework -LApplicationServices
		-L-framework -LCarbon"
	;;
*)
	EXTRA=""
	;;
esac

# Generated on demand so the tests can run on a fresh checkout.
[ -f src/keynavish/versioninfo.d ] || "$SCRIPT_DIR/generate-version-info.sh"

# Every source except main.d, which carries the application's entry point.
SOURCES=$(find src -name '*.d' ! -name 'main.d')

STATUS=0

for test in $TESTS; do
	printf '\n=== %s ===\n' "$test"

	# shellcheck disable=SC2086
	ldc2 -I=src -J=. -of="build/${test}_test" \
		"tests/${test}_test.d" $SOURCES $EXTRA 2>&1 |
		grep -v 'search path' || true

	# Noise from CoreFoundation when running outside a full GUI session.
	if ! "./build/${test}_test" 2>&1 |
		grep -vE 'hiservices-xpcservice|Error received in message reply handler'; then
		STATUS=1
	fi
done

printf '\n'
if [ "$STATUS" -eq 0 ]; then
	echo "all test suites passed"
else
	echo "SOME TEST SUITES FAILED"
fi

exit "$STATUS"
