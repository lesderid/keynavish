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

TESTS="${*:-config grid keys render}"

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

	# A stale binary from a previous run must not survive a failed build and
	# silently get re-run below.
	rm -f "build/${test}_test"

	# Output goes to a file rather than through a pipe, so the status checked
	# here is the compiler's and not grep's.
	# shellcheck disable=SC2086
	if ldc2 -I=src -J=. -of="build/${test}_test" \
		"tests/${test}_test.d" $SOURCES $EXTRA >"build/${test}_build.log" 2>&1
	then
		grep -v 'search path' "build/${test}_build.log" || true
	else
		grep -v 'search path' "build/${test}_build.log" || true
		echo "    BUILD FAILED"
		STATUS=1
		continue
	fi

	# Same again for the test itself: its exit status decides pass/fail, and
	# the saved output is filtered only for display. Filtering inline would
	# report grep's status instead, so a failing test that printed nothing
	# matching would look like a pass.
	if ! "./build/${test}_test" >"build/${test}_run.log" 2>&1; then
		STATUS=1
	fi

	# Noise from CoreFoundation when running outside a full GUI session.
	grep -vE 'hiservices-xpcservice|Error received in message reply handler' \
		"build/${test}_run.log" || true
done

# Cheap, and catches Windows breakage from a macOS-only change.
printf '\n=== windows type check ===\n'
if ! "$SCRIPT_DIR/check-windows.sh"; then
	STATUS=1
fi

printf '\n'
if [ "$STATUS" -eq 0 ]; then
	echo "all test suites passed"
else
	echo "SOME TEST SUITES FAILED"
fi

exit "$STATUS"
