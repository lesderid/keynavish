#!/bin/sh
#
# Builds keynavish.app for macOS, universal (arm64 + x86_64) where the toolchain
# supports it.
#
# Usage: tools/build-macos.sh [debug|release]
#
# Universal builds need x86_64 druntime and phobos. Homebrew's ldc ships
# arm64-only runtime libraries, so it can only produce an arm64 slice; use the
# official ldc2-*-osx-universal release for both.
#
# Signing: set KEYNAVISH_SIGN_IDENTITY to a stable certificate. Without one the
# bundle is ad-hoc signed, which runs but loses its Accessibility grant on every
# rebuild.
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

# Probed by compiling and linking a trivial program rather than by looking for
# runtime libraries on disk: the two LDC distributions lay them out differently,
# so a path-based check silently mis-detects one or the other.
can_build_arch() {
	probe_dir=$(mktemp -d)
	printf 'void main() {}\n' > "$probe_dir/probe.d"

	if ldc2 -mtriple="$1-apple-macos13" \
		-of="$probe_dir/probe" "$probe_dir/probe.d" >/dev/null 2>&1; then
		rm -rf "$probe_dir"
		return 0
	fi

	rm -rf "$probe_dir"
	return 1
}

# Both slices are probed rather than assuming the host one works.
SLICES=""
for arch in arm64 x86_64; do
	if can_build_arch "$arch"; then
		SLICES="$SLICES $arch"
	fi
done

if [ -z "$SLICES" ]; then
	echo "error: this ldc can build neither arm64 nor x86_64 for macOS 13." >&2
	echo "       install the official ldc2-*-osx-universal release." >&2
	exit 1
fi

case "$SLICES" in
*arm64*x86_64*) ;;
*)
	echo "note: this ldc can only build:$SLICES"
	echo "      for a universal build, install the official ldc2-*-osx-universal release."
	;;
esac

BUILT=""
for arch in $SLICES; do
	echo "==> building $arch"
	# Each slice is bundled once, below, after lipo -- not per architecture.
	KEYNAVISH_SKIP_BUNDLE=1 dub build --compiler=ldc2 --build="$BUILD_TYPE" --arch="$arch-apple-macos13" --force
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
