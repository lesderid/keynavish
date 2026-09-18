module keynavish.config;

version (Windows)
{
    public import core.sys.windows.windows : RGB;
}
else
{
    // Same packing as the Win32 macro (0x00BBGGRR), so the colour constants
    // below are shared verbatim between platforms.
    uint RGB(ubyte r, ubyte g, ubyte b)
    {
        return r | (g << 8) | (b << 16);
    }
}

ubyte redOf(uint colour)   { return cast(ubyte)(colour & 0xFF); }
ubyte greenOf(uint colour) { return cast(ubyte)((colour >> 8) & 0xFF); }
ubyte blueOf(uint colour)  { return cast(ubyte)((colour >> 16) & 0xFF); }

version (Windows)
{
    enum windowClassName = "keynavish-grid"w;

    // Windows composites the overlay with a colour key because layered windows
    // have no real alpha. macOS composites properly, so it has no equivalent.
    enum windowColourKey = RGB(255, 0, 255);

    static assert(windowColourKey != mainPenColour, "Colour key and main pen colour can't be the same");
    static assert(windowColourKey != borderPenColour, "Colour key and border pen colour can't be the same");
}

enum mainPenColour = RGB(30, 64, 64);
enum mainPenWidth = 1;
enum borderPenColour = RGB(255, 255, 255);
enum borderPenWidth = 1;

enum gridNavLabelColour = RGB(0, 51, 0);
enum gridNavLabelSelectedColour = RGB(0, 77, 77);
enum gridNavTextColour = RGB(204, 204, 204);
enum gridNavTextSelectedColour = RGB(255, 255, 255);

// Kept as a wstring: the Windows code passes programName.ptr straight to the
// Win32 W APIs. macOS converts to UTF-8 at the shim boundary instead.
enum programName = "keynavish"w;

version (Windows)
{
    enum programTagline = " – Control the mouse with the keyboard, on Windows."w;
}
else
{
    enum programTagline = " – Control the mouse with the keyboard, on macOS."w;
}

enum programInfo = programName ~ programTagline ~ "\n\nCopyright © 2021, Les De Ridder <les@lesderid.net>\n"w
                   ~ "Home page: <"w ~ programUrl ~ ">"w;
enum programUrl = "https://github.com/lesderid/keynavish";

version (Windows)
{
    enum usageHelpString = "Usage: " ~ programName ~ ".exe [options] [optional-startup-commands]\r\n" ~
    "Example: " ~ programName ~ ".exe \"loadconfig ~/myconfigs/keynavrc,loadconfig ~/myconfigs/anotherkeynavrc\"\r\n";
}
else
{
    enum usageHelpString = "Usage: " ~ programName ~ " [options] [optional-startup-commands]\n" ~
    "Example: " ~ programName ~ " \"loadconfig ~/myconfigs/keynavrc,loadconfig ~/myconfigs/anotherkeynavrc\"\n";
}

enum configFilePaths = ["~/.keynavrc", "~/keynavrc", "~/.config/keynav/keynavrc"];

version (Windows)
{
    enum unhandledExceptionMessage = "This is a bug, please press Ctrl+C and report it at https://github.com/lesderid/keynavish/issues/new.";
}
else
{
    enum unhandledExceptionMessage = "This is a bug, please report it at https://github.com/lesderid/keynavish/issues/new.";
}

version (OSX)
{
    // SF Symbol used for the menu bar item.
    enum statusItemSymbolName = "cursorarrow.rays";
}
