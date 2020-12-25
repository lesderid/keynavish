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

string[][] parseCommaDelimitedCommands(string input)
{
    import std.csv : csvReader, Malformed;
    import std.algorithm : map;
    import std.array : array;
    import std.string : strip;
    import std.exception : assumeWontThrow;

    //abusing csvReader so quoted strings are handled properly
    return input.csvReader!(string, Malformed.ignore).front
                .map!strip
                .map!(c => c.csvReader!(string, Malformed.ignore)(' ').front.array)
                .array.assumeWontThrow;
}