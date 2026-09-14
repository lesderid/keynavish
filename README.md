# keynavish

[![Latest release](https://img.shields.io/github/v/release/lesderid/keynavish?sort=semver)](https://github.com/lesderid/keynavish/releases/latest)
[![CI build status](https://img.shields.io/github/actions/workflow/status/lesderid/keynavish/ci.yml)](https://github.com/lesderid/keynavish/actions?query=workflow%3ACI)
[![Compatibility issues](https://img.shields.io/github/issues/lesderid/keynavish/compatibility)](https://github.com/lesderid/keynavish/labels/compatibility)

Control the mouse with the keyboard, on Windows and macOS.

This is a rewrite of [keynav](https://github.com/jordansissel/keynav)
for Windows and macOS. It is fully compatible with the original (modulo
[bugs](https://github.com/lesderid/keynavish/labels/compatibility)),
so you can use the same configuration files for all of them.

keynavish works on Windows XP and later, but only versions of Windows
that still receive support from Microsoft (currently 8.1 and 10) are
officially supported.

On macOS, keynavish requires macOS 13 (Ventura) or later.

## Demo

[![Demo](https://lesderid.net/keynavish-demo.gif)](https://lesderid.net/keynavish-demo.webm)

(click for full quality video)

## Installing

### Windows

You can 'install' keynavish by downloading the [latest
release](https://github.com/lesderid/keynavish/releases/latest)
executable, running it, and selecting `Launch keynavish on startup` from
the notification icon context menu.

### macOS

Download `keynavish.app` from the [latest
release](https://github.com/lesderid/keynavish/releases/latest), move it
to `/Applications`, and run it. keynavish appears in the menu bar; there
is no Dock icon.

**keynavish needs Accessibility permission** to see key presses at all.
macOS will prompt on first launch; if you miss the prompt, open
`System Settings -> Privacy & Security -> Accessibility` and enable
keynavish there. You do not need to restart it -- keynavish starts
working as soon as you grant permission. Until then its menu bar icon is
dimmed and its menu says so.

Select `Launch keynavish on startup` from the menu bar item to have it
start automatically.

## Configuration

Configuration format: [keynav
documentation](https://github.com/jordansissel/keynav/blob/master/keynav.pod)

On startup, keynavish loads a set of
[default keybindings](https://github.com/lesderid/keynavish/blob/9cce3b7c8ae03791f8ef3aedcc3015bde2f8a054/src/keynavish/keyboardinput.d#L11-L51)
, and then tries
to load the following configuration files:

* `<executable path>/keynavrc` (Windows, for portability) or
  `keynavish.app/Contents/Resources/keynavrc` (macOS, a read-only default)
* `~/.keynavrc`
* `~/keynavrc`
* `~/.config/keynav/keynavrc`

Later files layer over earlier ones, so your own `~/.keynavrc` overrides
the bundled defaults.

On Windows, tildes (`~`) in paths are expanded to the value of `%HOME%`
if it's set, with fallback to `%USERPROFILE%` (usually
`C:\Users\<username>`). On macOS they expand to `$HOME`.

### macOS differences

The configuration format is identical, and the same `keynavrc` is meant
to work on every platform. A few things behave differently because macOS
does:

* `super` is the Command key, and `alt` is Option.
* `record` and `playback` are not implemented yet. Configs using them
  still load and everything else works; those bindings simply do nothing.
* `Insert` has no macOS equivalent and maps to the Help key.
* While an application has secure input enabled (password fields, some
  terminals), macOS delivers no key events to any observer, so keynavish
  will appear unresponsive until you leave that field.
* The grid is drawn above everything, including full-screen apps -- and
  also above system alerts while it is visible. It never receives input,
  so this is cosmetic.

## Building

### Windows

Install [dub](https://dub.pm/) and run `dub build`.

For development, using [VisualD](https://rainers.github.io/visuald/)
with the supplied solution file is recommended.

### macOS

Install [LDC](https://github.com/ldc-developers/ldc) and
[dub](https://dub.pm/), then run:

```
tools/build-macos.sh
```

This builds the binary, assembles `out/keynavish.app`, and signs it. DMD
cannot be used: it has no native arm64 macOS backend.

For a universal (arm64 + x86_64) build you need the official
`ldc2-*-osx-universal` release rather than the Homebrew package, which
ships arm64-only runtime libraries. The script detects this and tells you.

To keep macOS from revoking keynavish's Accessibility permission on every
rebuild, sign with a stable certificate rather than ad-hoc:

```
KEYNAVISH_SIGN_IDENTITY="Your Certificate Name" tools/build-macos.sh
```

Run the test suites with:

```
tools/run-tests.sh
```

See [MACOS-PORT.md](MACOS-PORT.md) for the design of the macOS port.

## Contributing

If you'd like to contribute, thank you! Please feel free to make a pull
request (or open an issue), but make sure that your contribution does
not break compatibility with keynav. In particular, any changes to the
configuration format that are not compatible with keynav will generally
be rejected.

## License

keynavish is licensed under the [GNU GPLv2](/LICENSE).

For commercial licensing or support, please [contact
me](https://lesderid.net).
