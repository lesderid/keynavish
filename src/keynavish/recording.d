module keynavish.recording;

import keynavish;

import core.sys.windows.windows : DWORD;

@system nothrow:

struct Recording
{
    DWORD vkCode;
    string[][] commands;
    string path;

    string toString()
    {
        import std.algorithm : map;
        import std.string : join;
        import std.format : format;
        import std.exception : assumeWontThrow;

        return format!"%d %s\r\n"(vkCode, commands.map!(c => c.join(' ')).join(", ")).assumeWontThrow;
    }
}

Recording[] recordings;

bool waitingForRecordingKey;
Recording activeRecording;

bool replaying;

bool recordingActive()
{
    return activeRecording.vkCode != 0;
}

void loadRecordings()
{
    import std.algorithm : map, filter, joiner, splitter, findSplit, find;
    import std.file : exists, readText;
    import std.conv : to;
    import std.exception : assumeWontThrow;
    import std.array : replace, array;
    import std.csv : csvReader, Malformed;
    import std.string : strip;
    import std.format : format;
    import std.range : empty;

    () {
        foreach (path; regularKeyBindings.map!(b => b.commands)
                                         .joiner
                                         .filter!(c => c[0] == "record" && c.length == 2)
                                         .map!(c => expandPath(c[1]))
                                         .filter!(p => p.exists))
        {
            foreach (line; path.readText.replace('\r', "").splitter('\n'))
            {
                auto parts = line.findSplit(" ");

                if (parts[0].length == 0)
                    continue;

                auto vkCode = parts[0].to!DWORD.assumeWontThrow;

                auto commands = parts[2].parseCommaDelimitedCommands();

                auto recording = Recording(vkCode, commands, path);
                auto recordingRange = recordings.find!(r => r.vkCode == vkCode);
                if (!recordingRange.empty)
                {
                    showWarning(format!"More than one recording found for key code '%d', last one will be used!"(vkCode).assumeWontThrow);
                    recordingRange[0] = recording;
                }
                else
                {
                    recordings ~= recording;
                }
            }
        }
    }().assumeWontThrow;
}

void startReplaying()
{
    replaying = true;
}

void replay(DWORD vkCode)
{
    import std.algorithm : find;
    import std.range : empty;
    import std.exception : assumeWontThrow;
    import std.format : format;

    auto recordingRange = recordings.find!(r => r.vkCode == vkCode);
    if (recordingRange.empty)
    {
        showWarning(format!"No recording found for key code '%d'!"(vkCode).assumeWontThrow);
    }
    else
    {
        processCommands(recordingRange[0].commands);
    }

    replaying = false;
}

void startRecording(string path)
{
    waitingForRecordingKey = true;

    activeRecording.path = path.expandPath;
}

void stopRecording()
{
    import std.algorithm : find, filter, map;
    import std.range: empty;
    import std.array : join;
    import std.file : write, exists;
    import std.exception : assumeWontThrow;
    import std.path : dirName;

    auto recordingRange = recordings.find!(r => r.vkCode == activeRecording.vkCode);
    if (recordingRange.empty)
    {
        recordings ~= activeRecording;
    }
    else
    {
        recordingRange[0] = activeRecording;
    }

    if (activeRecording.path != null)
    {
        auto recordingText = recordings.filter!(r => r.path == activeRecording.path).map!(r => r.toString).join.assumeWontThrow;

        if (!activeRecording.path.dirName.exists)
        {
            showError("Can't save recording, parent dir doesn't exist: " ~ activeRecording.path.dirName);
        }
        else
        {
            activeRecording.path.write(recordingText).assumeWontThrow;
        }
    }

    activeRecording = Recording();
}

void setRecordingKey(DWORD vkCode)
{
    activeRecording.vkCode = vkCode;

    waitingForRecordingKey = false;
}

void recordCommands(string[][] commands)
{
    foreach (command; commands)
    {
        if (command[0] == "record")
        {
            break;
        }

        activeRecording.commands ~= command;
    }
}