module keynavish.grid;

import core.sys.windows.windows : RECT, HDC, HPEN;
import std.container : SList;
import std.typecons : Tuple;
import keynavish;

struct Grid
{
    RECT rect;
    int rows;
    int columns;
}

private Grid grid_;
private SList!Grid gridStack;

HPEN mainPen;
HPEN borderPen;

@property
Tuple!(int, "width", int, "height") primaryDeviceResolution()
{
    import core.sys.windows.windows : GetDC, GetDeviceCaps, HORZRES, VERTRES;

    auto rootDeviceContext = GetDC(null);

    auto resolution = typeof(return)();
    resolution.width = GetDeviceCaps(rootDeviceContext, HORZRES);
    resolution.height = GetDeviceCaps(rootDeviceContext, VERTRES);

    return resolution;
}

@property
RECT[] displayRectangles()
{
    import core.sys.windows.windows : EnumDisplayMonitors, MONITORENUMPROC, BOOL, TRUE, HMONITOR, HDC, LPRECT, LPARAM;

    RECT[] displayRectangles = [];

    static extern(Windows) BOOL callback(HMONITOR, HDC, LPRECT rectangle, LPARAM userData)
    {
        RECT[]* displayRectangles = cast(RECT[]*) cast(void*) userData;

        *displayRectangles ~= *rectangle;

        return TRUE;
    }

    EnumDisplayMonitors(null, null, &callback, cast(LPARAM) cast(void*) &displayRectangles);

    return displayRectangles;
}

@property
Tuple!(int, "width", int, "height", int, "left", int, "top") virtualScreenRectangle()
{
    import core.sys.windows.windows : GetSystemMetrics, SM_CXVIRTUALSCREEN, SM_CYVIRTUALSCREEN, SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN;

    auto virtualScreen = typeof(return)();
    virtualScreen.width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    virtualScreen.height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    virtualScreen.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    virtualScreen.top = GetSystemMetrics(SM_YVIRTUALSCREEN);

    return virtualScreen;
}

const(Grid) grid()
{
    return grid_;
}

void grid(Grid newGrid)
{
    if (newGrid == grid) return;

    gridStack.insertFront(grid);
    grid_ = newGrid;
}

void tryPopGrid()
{
    if (gridStack.empty) return;

    grid_ = gridStack.front;
    gridStack.removeFront();
}

void resetGrid()
{
    import core.sys.windows.windows : POINT, GetCursorPos;
    import std.algorithm : find;
    import std.range : empty;

    POINT cursorPosition;
    auto result = GetCursorPos(&cursorPosition);
    assert(result);

    auto cursorScreen = displayRectangles.find!(r => r.contains(cursorPosition));
    assert(!cursorScreen.empty);

    grid_.rect = cursorScreen[0];
    grid_.rows = 2;
    grid_.columns = 2;
    gridStack = typeof(gridStack)();
}

private const(RECT[]) splitGrid()
{
    import std.algorithm : cartesianProduct, map;
    import std.range : array, iota;

    auto x = grid.rect.left;
    auto y = grid.rect.top;
    auto width = grid.rect.width / grid.columns;
    auto height = grid.rect.height / grid.rows;

    return cartesianProduct(grid.columns.iota, grid.rows.iota).map!(t => t.rename!("x", "y"))
            .map!(t => RECT(x + t.x * width, y + t.y * height, x + (t.x + 1) * width, y + (t.y + 1) * height))
            .array;
}

void paintGrid(HDC deviceContext)
{
    import core.sys.windows.windows : DWORD, POINT, PolyPolyline, SelectObject;
    import std.algorithm : map;
    import std.range : repeat, join, array;

    auto virtualScreen = virtualScreenRectangle;

    auto pointArrays = splitGrid.map!(r => [
        POINT(r.left, r.top),
        POINT(r.right, r.top),
        POINT(r.right, r.bottom),
        POINT(r.left, r.bottom),
        POINT(r.left, r.top)
    ].map!(p => POINT(p.x - virtualScreen.left, p.y - virtualScreen.top))).join;

    DWORD[] sizes = uint(5).repeat(pointArrays.length).array;

    SelectObject(deviceContext, borderPen);
    PolyPolyline(deviceContext, pointArrays.ptr, sizes.ptr, grid.columns * grid.rows);

    SelectObject(deviceContext, mainPen);
    PolyPolyline(deviceContext, pointArrays.ptr, sizes.ptr, grid.columns * grid.rows);
}