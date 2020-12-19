module keynavish.helpers;

import keynavish;
import core.sys.windows.windows;

@system nothrow:

LONG width(RECT rect)
{
    return rect.right - rect.left;
}

LONG height(RECT rect)
{
    return rect.bottom - rect.top;
}

string expandPath(string inputString)
{
    import std.process : environment;
    import std.algorithm : canFind;
    import std.array : replace;
    import std.exception : assumeWontThrow;

    if (inputString.canFind('~').assumeWontThrow)
    {
        auto homeDir = environment.get("HOME", environment.get("USERPROFILE")).assumeWontThrow;

        if (homeDir is null)
        {
            showWarning(inputString ~ ": USERPROFILE and HOME environment variables both missing, defaulting to working dir for path expansion");
            homeDir = ".";
        }

        inputString = inputString.replace("~", homeDir);
    }

    return inputString.replace("/", "\\");
}