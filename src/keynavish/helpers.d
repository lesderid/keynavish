module keynavish.helpers;

import keynavish;
import keynavish.types;

int width(Rect rect)
{
    return rect.right - rect.left;
}

int height(Rect rect)
{
    return rect.bottom - rect.top;
}

bool contains(Rect rect, Point point)
{
    return point.x >= rect.left && point.x < rect.right &&
           point.y >= rect.top && point.y < rect.bottom;
}

bool isEmpty(Rect rect)
{
    return rect.width <= 0 || rect.height <= 0;
}

string expandPath(string inputString)
{
    import std.process : environment;
    import std.algorithm : canFind;
    import std.array : replace;

    if (inputString.canFind('~'))
    {
        version (Windows)
        {
            auto homeDir = environment.get("HOME", environment.get("USERPROFILE"));

            if (homeDir is null)
            {
                showWarning(inputString ~ ": USERPROFILE and HOME environment variables both missing, defaulting to working dir for path expansion");
                homeDir = ".";
            }
        }
        else
        {
            import keynavish.platform.macos.shim : knv_home_directory;
            import core.stdc.string : strlen;

            auto homeDir = environment.get("HOME");

            if (homeDir is null)
            {
                auto nsHome = knv_home_directory();
                homeDir = nsHome is null ? null : nsHome[0 .. strlen(nsHome)].idup;
            }

            if (homeDir is null)
            {
                showWarning(inputString ~ ": HOME environment variable missing and NSHomeDirectory() unavailable, defaulting to working dir for path expansion");
                homeDir = ".";
            }
        }

        inputString = inputString.replace("~", homeDir);
    }

    version (Windows)
    {
        return inputString.replace("/", "\\");
    }
    else
    {
        return inputString;
    }
}

string[][] parseCommaDelimitedCommands(string input)
{
    import std.csv : csvReader, Malformed;
    import std.algorithm : map;
    import std.array : array;
    import std.string : strip;

    //abusing csvReader so quoted strings are handled properly
    return input.csvReader!(string, Malformed.ignore).front
                .map!strip
                .map!(c => c.csvReader!(string, Malformed.ignore)(' ').front.array)
                .array;
}
