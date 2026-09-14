module keynavish.main;

static import std.getopt;
import keynavish;
import keynavish.platform;

version (Windows)
{
    import core.sys.windows.windows;

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
        registerWindowClass();
        createGdiObjects();
    }

    extern(C)
    int _main(string[] args)
    {
        return runKeynavish(args);
    }
}
else
{
    int main(string[] args)
    {
        return runKeynavish(args);
    }
}

int runKeynavish(string[] args)
{
    version (OSX)
    {
        import keynavish.platform.macos.shim : knv_app_init;

        // NSApplication has to exist before any window or status item is
        // created, and before the run loop the event tap attaches to.
        knv_app_init();
    }

    loadAllConfigs();

    if (handleArgsAndContinue(args))
    {
        createWindow();

        resetGrid();

        addNotifyIcon();

        // On Windows the hook always installs. On macOS it needs Accessibility
        // permission, so a failure here is the normal first-run state rather
        // than an error: keep running and poll until the user grants it, then
        // install the tap without needing a restart. See MACOS-PORT.md §7.1.
        if (!installKeyboardHook())
        {
            startPermissionPolling();
            rebuildStatusMenu();
        }

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

    version (Windows)
    {
        enum separator = "\r\n\r\n"w;
    }
    else
    {
        enum separator = "\n\n"w;
    }

    defaultGetoptFormatter(helpAppender, (programInfo ~ separator ~ usageHelpString).to!string, getoptOptions);

    showInfo(helpAppender[]);
}

void showVersion()
{
    import std.conv : to;

    showInfo(programName.to!string ~ " " ~ gitVersion);
}

void messageLoop()
{
    version (Windows)
    {
        MSG msg;
        while (GetMessage(&msg, null, 0, 0) && !quitting)
        {
            DispatchMessage(&msg);
        }
    }
    else
    {
        import keynavish.platform.macos.shim : knv_run;

        // [NSApp run] drives the same CFRunLoop the event tap source is
        // attached to. It does not return: terminate exits the process.
        knv_run();
    }
}
