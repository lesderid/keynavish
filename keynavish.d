module keynavish.keynavish;

import core.sys.windows.windows;
import keynavish.config;
import keynavish.keyboardinput;
import keynavish.helpers;

@system nothrow:

HWND windowHandle;

HPEN pen;

int screenWidth;
int screenHeight;

RECT gridRect;

bool active;

static this()
{
    registerWindowClass();
    registerKeyboardHook();

    pen = CreatePen(PS_SOLID, penWidth, penColour);

    auto rootDeviceContext = GetDC(null);
    screenWidth = GetDeviceCaps(rootDeviceContext, HORZRES);
    screenHeight = GetDeviceCaps(rootDeviceContext, VERTRES);

    //TODO: Read keybinds from config file
    registerKeyBinding("ctrl+semicolon start #start on ctrl+;");
    registerKeyBinding("ctrl+period start #start on ctrl+. too (for other keyboard layouts)");
    registerKeyBinding("Escape end #end on esc");
    registerKeyBinding("Left cut-left");
    registerKeyBinding("Down cut-down");
    registerKeyBinding("Up cut-up");
    registerKeyBinding("Right cut-right");
    registerKeyBinding("shift+Left move-left");
    registerKeyBinding("shift+Down move-down");
    registerKeyBinding("shift+Up move-up");
    registerKeyBinding("shift+Right move-right");
    registerKeyBinding("y cut-left,cut-up");
    registerKeyBinding("space warp,click 1,end");
    registerKeyBinding("alt+space warp,click 2,end");
    registerKeyBinding("shift+space warp,click 3,end");
    registerKeyBinding("d warp,doubleclick 1,end");
    registerKeyBinding("alt+d warp,doubleclick 2,end");
    registerKeyBinding("shift+d warp,doubleclick 3,end");
    registerKeyBinding("semicolon warp,end");
    registerKeyBinding("period warp,end");
    registerKeyBinding("c cursorzoom 200 200");
    registerKeyBinding("w windowzoom");
    registerKeyBinding("super+t toggle-start");
    registerKeyBinding("q quit");
    registerKeyBinding("r restart");
    registerKeyBinding("u sh \"explorer %USERPROFILE%\"");
}

void run()
{
    createWindow();

    resetGrid();

    MSG msg;
    while (GetMessage(&msg, null, 0, 0))
    {
        DispatchMessage(&msg);
    }
}

void registerWindowClass()
{
    WNDCLASSEX windowsClassEx;
    windowsClassEx.style = CS_HREDRAW | CS_VREDRAW;
    windowsClassEx.lpfnWndProc = &windowProc;
    windowsClassEx.hInstance = GetModuleHandle(null);
    windowsClassEx.hbrBackground = CreateSolidBrush(windowColourKey);
    windowsClassEx.lpszClassName = windowClassName.ptr;

    RegisterClassEx(&windowsClassEx);
}

void createWindow()
{
    windowHandle = CreateWindowEx(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT,
                                  windowClassName.ptr,
                                  "keynavish"w.ptr,
                                  WS_POPUP,
                                  0,
                                  0,
                                  screenWidth,
                                  screenHeight,
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

void resetGrid()
{
    gridRect = RECT(0, 0, screenWidth, screenHeight);
}

void paintGrid(HDC deviceContext)
{
    SelectObject(deviceContext, pen);

    auto x = gridRect.left;
    auto y = gridRect.top;
    auto w = gridRect.width / 2;
    auto h = gridRect.height / 2;

    //clockwise
    POINT[] points = [
        {x, y}, {x + w, y}, {x + w, y + h}, {x, y + h}, {x, y},
        {x + w, y}, {x + 2 * w, y}, {x + 2 * w, y + h}, {x + w, y + h}, {x + w, y},
        {x + w, y + h}, {x + 2 * w, y + h}, {x + 2 * w, y + 2 * h}, {x + w, y + 2 * h}, {x + w, y + h},
        {x, y + h}, {x + w, y + h}, {x + w, y + 2 * h}, {x, y + 2 * h}, {x, y + h},
    ];
    DWORD[] sizes = [5, 5, 5, 5];
    PolyPolyline(deviceContext, points.ptr, sizes.ptr, 4);
}

extern(Windows)
LRESULT windowProc(HWND handle, UINT message, WPARAM wParam, LPARAM lParam)
{
    assert(handle == windowHandle || windowHandle == null);

    switch (message)
    {
        case WM_PAINT:
            PAINTSTRUCT ps;
            auto deviceContext = BeginPaint(handle, &ps);
            paintGrid(deviceContext);
            EndPaint(handle, &ps);
            break;
        case WM_DESTROY:
            PostQuitMessage(0);
            break;
        default:
            return DefWindowProc(handle, message, wParam, lParam);
    }
    return 0;
}
