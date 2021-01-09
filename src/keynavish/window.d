module keynavish.window;

import core.sys.windows.windows;
import keynavish;

HWND windowHandle;

bool active;
bool quitting;

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
        case WM_QUIT:
            quitting = true;
            break;
        case WM_USER:
            handleNotifyIconMessage(wParam, lParam);
            break;
        default:
            return DefWindowProc(handle, message, wParam, lParam);
    }
    return 0;
}
