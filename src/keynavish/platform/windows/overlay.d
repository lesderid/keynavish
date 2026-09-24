module keynavish.platform.windows.overlay;

version (Windows):

import core.sys.windows.windows;
import keynavish;
import keynavish.types;
import keynavish.platform.windows.display;

//
// The overlay window, plus the GDI drawing primitives that the shared paintGrid
// in grid.d calls.
//

alias Canvas = HDC;

struct TextSize
{
    int width;
    int height;
}

HWND windowHandle;

bool active;
bool quitting;

UINT taskbarCreatedMessage;

private HPEN mainPen;
private HPEN borderPen;
private HFONT labelFont;

void registerWindowClass()
{
    WNDCLASSEX windowsClassEx;
    windowsClassEx.style = CS_HREDRAW | CS_VREDRAW;
    windowsClassEx.lpfnWndProc = &exceptionHandlerWrapper!windowProc;
    windowsClassEx.hInstance = GetModuleHandle(null);
    windowsClassEx.hbrBackground = CreateSolidBrush(windowColourKey);
    windowsClassEx.lpszClassName = windowClassName.ptr;

    RegisterClassEx(&windowsClassEx);
}

void createGdiObjects()
{
    mainPen = CreatePen(PS_SOLID, mainPenWidth, mainPenColour);
    borderPen = CreatePen(PS_SOLID, borderPenWidth * 2 + mainPenWidth, borderPenColour);
    labelFont = CreateFont(18, 0, 0, 0, FW_BOLD, false, false, false, DEFAULT_CHARSET,
                           OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                           FIXED_PITCH | FF_MODERN, "Courier New"w.ptr);
}

void createWindow()
{
    auto resolution = virtualScreenRectangle;

    windowHandle = CreateWindowEx(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOPMOST,
                                  windowClassName.ptr,
                                  programName.ptr,
                                  WS_POPUP,
                                  0,
                                  0,
                                  resolution.width,
                                  resolution.height,
                                  null,
                                  null,
                                  GetModuleHandle(null),
                                  null);

    SetLayeredWindowAttributes(windowHandle, windowColourKey, 0, LWA_COLORKEY);
    SetWindowPos(windowHandle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
}

void showWindow()
{
    active = true;

    ShowWindow(windowHandle, SW_SHOW);
    UpdateWindow(windowHandle);
}

void hideWindow()
{
    active = false;

    ShowWindow(windowHandle, SW_HIDE);
    UpdateWindow(windowHandle);
}

void redrawWindow()
{
    if (windowHandle == null) return;

    InvalidateRect(windowHandle, null, true);
}

/// Repositions the overlay to cover the whole virtual screen. Called on start,
/// since the display arrangement may have changed since the window was created.
void moveOverlayToVirtualScreen()
{
    auto virtualScreen = virtualScreenRectangle;

    MoveWindow(windowHandle, virtualScreen.left, virtualScreen.top,
               virtualScreen.width, virtualScreen.height, false);
}

extern(Windows)
LRESULT windowProc(HWND handle, UINT message, WPARAM wParam, LPARAM lParam)
{
    assert(handle == windowHandle || windowHandle == null);

    switch (message)
    {
        case WM_CREATE:
            taskbarCreatedMessage = RegisterWindowMessage("TaskbarCreated");
            goto default;
        case WM_PAINT:
            PAINTSTRUCT ps;
            auto deviceContext = BeginPaint(handle, &ps);
            auto virtualScreen = virtualScreenRectangle;
            paintGrid(deviceContext, Point(virtualScreen.left, virtualScreen.top));
            EndPaint(handle, &ps);
            break;
        case WM_DESTROY:
        case WM_QUIT:
            quitting = true;
            break;
        case WM_USER:
            handleNotifyIconMessage(wParam, lParam);
            break;
        default:
            if (message == taskbarCreatedMessage)
            {
                removeNotifyIcon();
                addNotifyIcon();
            }

            return DefWindowProc(handle, message, wParam, lParam);
    }
    return 0;
}

//
// Drawing primitives used by the shared paintGrid in grid.d.
//

void strokeRectangles(Canvas canvas, const(Rect)[] rects, uint colour, int lineWidth)
{
    import std.algorithm : map;
    import std.range : repeat, join, array;

    auto pointArrays = rects.map!(r => [
        POINT(r.left, r.top),
        POINT(r.right, r.top),
        POINT(r.right, r.bottom),
        POINT(r.left, r.bottom),
        POINT(r.left, r.top)
    ]).join;

    DWORD[] sizes = uint(5).repeat(rects.length).array;

    // The two pens are pre-created rather than built per call, so the colour
    // selects which one is meant.
    SelectObject(canvas, colour == borderPenColour ? borderPen : mainPen);
    PolyPolyline(canvas, pointArrays.ptr, sizes.ptr, cast(DWORD) rects.length);
}

void fillRectangle(Canvas canvas, Rect rect, uint colour)
{
    auto oldBrush = SelectObject(canvas, GetStockObject(DC_BRUSH));
    scope (exit) SelectObject(canvas, oldBrush);

    SetDCBrushColor(canvas, colour);
    Rectangle(canvas, rect.left, rect.top, rect.right, rect.bottom);
}

TextSize measureLabel(Canvas canvas, const(char)[] text)
{
    import std.conv : to;
    import std.utf : toUTF16z;

    auto oldFont = SelectObject(canvas, cast(HGDIOBJ) labelFont);
    scope (exit) SelectObject(canvas, oldFont);

    SIZE size;
    GetTextExtentPoint32(canvas, text.to!string.toUTF16z, cast(int) text.length, &size);

    return TextSize(size.cx, size.cy);
}

void drawLabel(Canvas canvas, int x, int y, const(char)[] text, uint colour)
{
    import std.conv : to;
    import std.utf : toUTF16z;

    auto oldFont = SelectObject(canvas, cast(HGDIOBJ) labelFont);
    auto oldBkMode = SetBkMode(canvas, TRANSPARENT);
    scope (exit)
    {
        SelectObject(canvas, oldFont);
        SetBkMode(canvas, oldBkMode);
    }

    SetTextColor(canvas, colour);
    TextOut(canvas, x, y, text.to!string.toUTF16z, cast(int) text.length);
}

void quitApplication()
{
    PostQuitMessage(0);
}
