# keynavish

Control the mouse with the keyboard, on Windows.

This is a rewrite of [keynav](https://github.com/jordansissel/keynav)
for Windows.

keynavish is mainly tested on Windows 8, but most likely also works on
Windows 7 and Windows 10.

## Building

The project can be compiled with Visual Studio +
[VisualD](https://rainers.github.io/visuald/) with the supplied solution
file.

Alternatively, you can build the project with `dub build`.

## Configuration

keynavish uses the same configuration format as keynav. For more
details, please see the [keynav
documentation](https://github.com/jordansissel/keynav/blob/master/keynav.pod).

On startup, keynavish loads a set of default keybindings, and then
tries to load the following configuration files:

* `~/.keynavrc`
* `~/keynavrc`
* `~/.config/keynav/keynavrc`

Tildes (`~`) in paths are expanded to the value of `%HOME%` if it's set, with fallback to
`%USERPROFILE%` (usually `C:\Users\<username>`).

## Compatibility with keynav

keynavish is fully compatible with keynav (modulo bugs), so you can
simply copy over your keynavrc without having to make any changes.

Currently the `grid-nav` command is not implemented yet.

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
