module keynavish.main;

import core.sys.windows.windows;
static import std.getopt;
import keynavish;

alias extern(C) int function(string[] args) MainFunc;
extern (C) int _d_run_main(int argc, char **argv, MainFunc mainFunc);

int WinMain_(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    import std.algorithm : map;
    import std.conv : to;
    import std.array : array;
    import std.string : fromStringz;

    int argCount;
    wchar** wideArgs = CommandLineToArgvW(GetCommandLine(), &argCount);
    char** args = wideArgs[0 .. argCount].map!(cs => cs.fromStringz.to!(char[]).ptr).array.ptr;

    return _d_run_main(argCount, args, &_main);
}

extern(Windows)
int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    return exceptionHandlerWrapper!WinMain_(hInstance, hPrevInstance, lpCmdLine, nCmdShow);
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
    loadAllConfigs();

    if (handleArgsAndContinue(args))
    {
        createWindow();

        resetGrid();

        addNotifyIcon();

        messageLoop();

        removeNotifyIcon();
    }

    return 0;
}

bool handleArgsAndContinue(string[] args)
{
    import std.getopt;
    import std.algorithm : canFind;

    bool printVersion;
    auto getoptResult = getopt(args, config.passThrough, "version|V", "Program version information.", &printVersion);
    printVersion = printVersion || args.canFind("version");

    if (printVersion)
    {
        showVersion();
        return false;
    }
    else if (getoptResult.helpWanted || args.length > 2)
    {
        showHelp(getoptResult.options);
        return false;
    }
    else
    {
        if (args.length == 2)
        {
            auto commands = args[1].parseCommaDelimitedCommands();
            verifyCommands(commands) && processCommands(commands);
        }
        return true;
    }
}

void showHelp(std.getopt.Option[] getoptOptions)
{
    import std.getopt : defaultGetoptFormatter;
    import std.array : appender;
    import std.conv : to;

    auto helpAppender = appender!(char[]);
    defaultGetoptFormatter(helpAppender, (programInfo ~ "\r\n\r\n"w ~ usageHelpString).to!string, getoptOptions);

    showInfo(helpAppender[]);
}

void showVersion()
{
    showInfo(programName ~ " " ~ gitVersion);
}

void messageLoop()
{
    MSG msg;
    while (GetMessage(&msg, null, 0, 0) && !quitting)
    {
        DispatchMessage(&msg);
    }
}