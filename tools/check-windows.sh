#!/bin/sh
#
# Type-checks the Windows build from any platform.
#
# LDC can run full semantic analysis for a Windows target without linking, which
# needs no Windows SDK. It does not link, so it cannot catch a missing Win32
# import library symbol, and it is no substitute for running the thing.
#
# Usage: tools/check-windows.sh
#
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$SCRIPT_DIR")

cd "$ROOT"

command -v ldc2 >/dev/null 2>&1 || { echo "ldc2 not found (brew install ldc)" >&2; exit 1; }

# versioninfo.d is generated; the check needs it to exist.
[ -f src/keynavish/versioninfo.d ] || "$SCRIPT_DIR/generate-version-info.sh" >/dev/null

STATUS=0

for triple in x86_64-pc-windows-msvc i686-pc-windows-msvc; do
	printf '==> %s\n' "$triple"

	# -o- runs the full front end but writes no object file, so no linker and
	# no Windows SDK are needed.
	if ldc2 -mtriple="$triple" -o- -I=src -J=. $(find src -name '*.d'); then
		echo "    ok"
	else
		STATUS=1
	fi
done

if [ "$STATUS" -eq 0 ]; then
	echo "windows sources type-check"
else
	echo "WINDOWS TYPE CHECK FAILED"
fi

exit "$STATUS"
