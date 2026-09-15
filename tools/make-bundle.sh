#!/bin/sh
#
# Assembles out/keynavish.app around an already-built executable.
#
# Usage: tools/make-bundle.sh <path-to-executable> [output-dir]
#
# Signing: by default the bundle is signed ad-hoc, which is enough to run but
# NOT enough to keep an Accessibility grant across rebuilds -- macOS ties the
# grant to the code signature, and an ad-hoc signature changes every build, so
# the permission silently stops applying while the checkbox still looks ticked.
# Set KEYNAVISH_SIGN_IDENTITY to a stable certificate to avoid that.
# See MACOS-PORT.md §7.2.
#
set -eu

BINARY="${1:?usage: make-bundle.sh <executable> [output-dir]}"
OUTDIR="${2:-out}"
APP="$OUTDIR/keynavish.app"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$SCRIPT_DIR")

if [ ! -f "$BINARY" ]; then
	echo "make-bundle: no such executable: $BINARY" >&2
	exit 1
fi

VERSION=$(cd "$ROOT" && git describe --tags 2>/dev/null || echo "0.0.0")
# Info.plist version keys must be dot-separated digits only.
PLIST_VERSION=$(printf '%s' "${VERSION#v}" | sed 's/-.*//' | grep -E '^[0-9]+(\.[0-9]+)*$' || echo "0.0.0")

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/keynavish"
chmod +x "$APP/Contents/MacOS/keynavish"

sed "s/@VERSION@/$PLIST_VERSION/g" "$ROOT/tools/Info.plist.in" > "$APP/Contents/Info.plist"

# Bundled read-only default config, loaded before the ~ paths.
# See MACOS-PORT.md §6.11 (option D).
if [ -f "$ROOT/keynavrc" ]; then
	cp "$ROOT/keynavrc" "$APP/Contents/Resources/keynavrc"
fi

if [ -n "${KEYNAVISH_SIGN_IDENTITY:-}" ]; then
	# No explicit --timestamp: codesign already requests a secure timestamp for
	# Developer ID identities, and forcing one breaks the self-signed identity
	# recommended for development, which cannot use Apple's timestamp service.
	codesign --force --options runtime \
		--sign "$KEYNAVISH_SIGN_IDENTITY" "$APP"
	echo "make-bundle: signed with $KEYNAVISH_SIGN_IDENTITY"
else
	codesign --force --sign - "$APP"
	echo "make-bundle: ad-hoc signed (set KEYNAVISH_SIGN_IDENTITY for a stable signature)"
fi

echo "make-bundle: built $APP ($VERSION)"
