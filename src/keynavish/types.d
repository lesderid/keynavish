module keynavish.types;

//
// Geometry in the Win32 convention throughout: top-left origin, Y grows
// downward, coordinates in the virtual-screen (Windows) or global display
// (macOS Quartz) space. AppKit's bottom-left origin is converted at the window
// boundary only.
//
// On Windows these are aliases for RECT and POINT, so the Win32 calls that take
// RECT*/POINT* by pointer keep working unchanged.
//

version (Windows)
{
    public import core.sys.windows.windows : Rect = RECT, Point = POINT;
}
else
{
    struct Rect
    {
        int left;
        int top;
        int right;
        int bottom;
    }

    struct Point
    {
        int x;
        int y;
    }
}

/// A key identity as the platform reports it: a Windows virtual-key code, or a
/// macOS CGKeyCode.
version (Windows)
{
    import core.sys.windows.windows : DWORD;

    alias KeyCode = DWORD;
}
else
{
    alias KeyCode = uint;
}

enum ModifierKey
{
    none   = 0,
    ctrl   = 1 << 0,
    shift  = 1 << 1,
    alt    = 1 << 2,
    super_ = 1 << 3,
}

struct Colour
{
    ubyte r;
    ubyte g;
    ubyte b;
}
