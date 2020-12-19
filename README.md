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

TODO

## Compatibility with keynav

keynavish aims to support everything keynav does, so you can simply copy
over your keynavrc without having to make any changes.

Any behaviour that is different or any feature that isn't implemented is
a bug.

Currently only basic functionality is implemented. More specifically,
`grid-nav`, `loadconfig`, `record`, and `playback` aren't implemented
yet.

## Known issues/bugs

TODO: Move these to GitHub issues

* Not DPI aware
* Most likely doesn't work properly with multiple displays
* Some spurious use of `assertWontThrow`
* Dragging with a modifier (`ctrl`, `shift`, etc.) doesn't work properly
* Not all X key names are supported yet

Pull requests (or issues with more information) would be much
appreciated.

## License

keynavish is licensed under the [GNU GPLv2](/LICENSE).

For commercial licensing or support, please [contact
me](https://lesderid.net).
