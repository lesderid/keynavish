module keynavish.main;

import core.sys.windows.windows;
import keynavish;

@system nothrow:

alias extern(C) int function(string[] args) MainFunc;
extern (C) int _d_run_main(int argc, char **argv, MainFunc mainFunc);

extern (Windows)
int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    return _d_run_main(0, null, &_main); // arguments unused, retrieved via CommandLineToArgvW
}

static this()
{
    import core.sys.windows.windows : CreatePen, GetDC, GetDeviceCaps, PS_SOLID, HORZRES, VERTRES;

    registerWindowClass();
    registerKeyboardHook();

    pen = CreatePen(PS_SOLID, penWidth, penColour);

    auto rootDeviceContext = GetDC(null);
    screenWidth = GetDeviceCaps(rootDeviceContext, HORZRES);
    screenHeight = GetDeviceCaps(rootDeviceContext, VERTRES);
}

extern(C)
int _main(string[] args)
{
    createWindow();

    resetGrid();

    messageLoop();

    return 0;
}

void messageLoop()
{
    MSG msg;
    while (GetMessage(&msg, null, 0, 0))
    {
        DispatchMessage(&msg);
    }
}