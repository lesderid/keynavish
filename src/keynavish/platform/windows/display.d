module keynavish.platform.windows.display;

version (Windows):

import keynavish.types;

//
// Display enumeration and cursor position. Moved verbatim from grid.d during
// the platform refactor; behaviour is unchanged.
//
// primaryDeviceResolution is deliberately gone: it existed only to normalise
// coordinates for MOUSEEVENTF_ABSOLUTE, and warp() now sends absolute virtual
// desktop coordinates instead. See MACOS-PORT.md §6.1.
//

@property
Rect[] displayRectangles()
{
    import core.sys.windows.windows : EnumDisplayMonitors, MONITORENUMPROC, BOOL, TRUE, HMONITOR, HDC, LPRECT, LPARAM;

    Rect[] displayRectangles = [];

    static extern(Windows) BOOL callback(HMONITOR, HDC, LPRECT rectangle, LPARAM userData)
    {
        Rect[]* displayRectangles = cast(Rect[]*) cast(void*) userData;

        *displayRectangles ~= *rectangle;

        return TRUE;
    }

    EnumDisplayMonitors(null, null, &callback, cast(LPARAM) cast(void*) &displayRectangles);

    return displayRectangles;
}

@property
Rect virtualScreenRectangle()
{
    import core.sys.windows.windows : GetSystemMetrics, SM_CXVIRTUALSCREEN, SM_CYVIRTUALSCREEN, SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN;

    auto left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    auto top = GetSystemMetrics(SM_YVIRTUALSCREEN);

    return Rect(left,
                top,
                left + GetSystemMetrics(SM_CXVIRTUALSCREEN),
                top + GetSystemMetrics(SM_CYVIRTUALSCREEN));
}

@property
Point cursorPosition()
{
    import core.sys.windows.windows : GetCursorPos;

    Point position;
    auto result = GetCursorPos(&position);
    assert(result);

    return position;
}

/// Primary display resolution, used only to normalise MOUSEEVENTF_ABSOLUTE
/// coordinates in warpCursor.
///
/// NOTE: this normalises against the primary display while the grid works in
/// virtual-screen coordinates, so warping onto a secondary monitor lands in the
/// wrong place on multi-monitor setups. That behaviour predates the macOS port
/// and is preserved here deliberately -- see MACOS-PORT.md §14.
@property
auto primaryDeviceResolution()
{
    import core.sys.windows.windows : GetDC, GetDeviceCaps, HORZRES, VERTRES;
    import std.typecons : Tuple;

    auto rootDeviceContext = GetDC(null);

    Tuple!(int, "width", int, "height") resolution;
    resolution.width = GetDeviceCaps(rootDeviceContext, HORZRES);
    resolution.height = GetDeviceCaps(rootDeviceContext, VERTRES);

    return resolution;
}
