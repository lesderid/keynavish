module keynavish.platform;

//
// Compile-time platform selection. No interfaces, no vtables, no runtime
// dispatch: a missing or mistyped platform function is a compile error at the
// call site. See MACOS-PORT.md §5.
//
// Only subsystems whose two implementations share no logic at all live in
// separate modules like this. Everything else uses inline version blocks in the
// shared module, which is the default.
//

version (Windows)
{
    public import keynavish.platform.windows.display;
    public import keynavish.platform.windows.overlay;
    public import keynavish.platform.windows.trayicon;
    public import keynavish.platform.windows.input;
    public import keynavish.platform.windows.keys;
}
else version (OSX)
{
    public import keynavish.platform.macos.display;
    public import keynavish.platform.macos.overlay;
    public import keynavish.platform.macos.statusitem;
    public import keynavish.platform.macos.input;
    public import keynavish.platform.macos.keys;
}
else
{
    static assert(false, "keynavish supports Windows and macOS only");
}
