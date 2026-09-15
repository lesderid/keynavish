#!/bin/sh
#
# Builds keynavish.app for macOS, universal (arm64 + x86_64) where the toolchain
# supports it.
#
# Usage: tools/build-macos.sh [debug|release]
#
# NOTE ON UNIVERSAL BUILDS: cross-compiling to x86_64 needs x86_64 druntime and
# phobos. Homebrew's ldc ships arm64-only runtime libraries, so it can only
# produce an arm64 slice. For a universal build use the official LDC release,
# which ships both:
#
#   https://github.com/ldc-developers/ldc/releases  (ldc2-*-osx-universal)
#
# This script detects what the installed toolchain can do and says so, rather
# than failing with a wall of linker errors.
#
# Signing: set KEYNAVISH_SIGN_IDENTITY to a stable certificate. Without one the
# bundle is ad-hoc signed, which runs but loses its Accessibility grant on every
# rebuild -- see MACOS-PORT.md §7.2.
#
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$SCRIPT_DIR")

cd "$ROOT"

BUILD_TYPE="${1:-debug}"

command -v ldc2 >/dev/null 2>&1 || { echo "ldc2 not found (brew install ldc)" >&2; exit 1; }
command -v dub  >/dev/null 2>&1 || { echo "dub not found (brew install dub)" >&2; exit 1; }

mkdir -p build out

# Keep dub's package cache inside the tree, so the build works without a
# writable ~/.dub (sandboxes, CI).
export DUB_HOME="${DUB_HOME:-$ROOT/build/dub-home}"
mkdir -p "$DUB_HOME"

# Can this LDC actually produce an x86_64 binary?
#
# Probed by compiling and linking a trivial program rather than by looking for
# runtime libraries on disk: Homebrew's ldc keeps them in ../lib while the
# official osx-universal release uses per-architecture lib-arm64 / lib-x86_64
# directories, so any path-based check silently mis-detects one layout or the
# other -- and mis-detecting here means quietly shipping a half-universal binary.
can_build_x86_64() {
	probe_dir=$(mktemp -d)
	printf 'void main() {}\n' > "$probe_dir/probe.d"

	if ldc2 -mtriple=x86_64-apple-macos13 \
		-of="$probe_dir/probe" "$probe_dir/probe.d" >/dev/null 2>&1; then
		rm -rf "$probe_dir"
		return 0
	fi

	rm -rf "$probe_dir"
	return 1
}

SLICES="arm64"
if can_build_x86_64; then
	SLICES="arm64 x86_64"
else
	echo "note: this ldc cannot build x86_64; building arm64 only."
	echo "      for a universal build, install the official ldc2-*-osx-universal release."
fi

BUILT=""
for arch in $SLICES; do
	echo "==> building $arch"
	dub build --compiler=ldc2 --build="$BUILD_TYPE" --arch="$arch-apple-macos13" --force
	mv out/keynavish "build/keynavish-$arch"
	BUILT="$BUILT build/keynavish-$arch"
done

# shellcheck disable=SC2086
set -- $BUILT
if [ "$#" -gt 1 ]; then
	echo "==> creating universal binary"
	lipo -create -output build/keynavish-final "$@"
else
	cp "$1" build/keynavish-final
fi

ARCHS=$(lipo -archs build/keynavish-final 2>/dev/null || echo unknown)
echo "==> built architectures: $ARCHS"

"$SCRIPT_DIR/make-bundle.sh" build/keynavish-final out
