# keynavish

[![Latest release](https://img.shields.io/github/v/release/lesderid/keynavish?sort=semver)](https://github.com/lesderid/keynavish/releases/latest)
[![CI build status](https://img.shields.io/github/actions/workflow/status/lesderid/keynavish/ci.yml)](https://github.com/lesderid/keynavish/actions?query=workflow%3ACI)
[![Compatibility issues](https://img.shields.io/github/issues/lesderid/keynavish/compatibility)](https://github.com/lesderid/keynavish/labels/compatibility)

Control the mouse with the keyboard, on Windows.

This is a rewrite of [keynav](https://github.com/jordansissel/keynav)
for Windows. It is fully compatible with the original (modulo
[bugs](https://github.com/lesderid/keynavish/labels/compatibility)),
so you can use the same configuration files for both programs.

keynavish works on Windows XP and later, but only versions of Windows
that still receive support from Microsoft (currently 8.1 and 10) are
officially supported.

## Demo

[![Demo](https://lesderid.net/keynavish-demo.gif)](https://lesderid.net/keynavish-demo.webm)

(click for full quality video)

## Installing

You can 'install' keynavish by downloading the [latest
release](https://github.com/lesderid/keynavish/releases/latest)
executable, running it, and selecting `Launch keynavish on startup` from
the notification icon context menu.

## Configuration

Configuration format: [keynav
documentation](https://github.com/jordansissel/keynav/blob/master/keynav.pod)

On startup, keynavish loads a set of
[default keybindings](https://github.com/lesderid/keynavish/blob/9cce3b7c8ae03791f8ef3aedcc3015bde2f8a054/src/keynavish/keyboardinput.d#L11-L51)
, and then tries
to load the following configuration files:

* `./keynavrc`
* `~/.keynavrc`
* `~/keynavrc`
* `~/.config/keynav/keynavrc`

Tildes (`~`) in paths are expanded to the value of `%HOME%` if it's set,
with fallback to `%USERPROFILE%` (usually `C:\Users\<username>`).

## Building

Install [dub](https://dub.pm/) and run `dub build`.

For development, using [VisualD](https://rainers.github.io/visuald/)
with the supplied solution file is recommended.

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
