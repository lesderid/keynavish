module keynavish.platform;

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
