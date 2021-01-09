module keynavish.commands;

import keynavish;

import core.sys.windows.windows : LONG, DWORD;

DWORD draggingFlag;

enum Direction
{
    up, down, left, right
}

Direction commandToDirection(string commandString)
{
    import std.algorithm : findSkip;
    findSkip(commandString, "-");
    switch (commandString)
    {
        case "up":    return Direction.up;
        case "down":  return Direction.down;
        case "left":  return Direction.left;
        case "right": return Direction.right;
        default:      assert(false);
    }
}

private void redrawWindow()
{
    //HACK: We should redraw properly somehow (RedrawWindow with RDW_INVALIDATE | RDW_UPDATENOW doesn't remove old grid)
    hideWindow();
    showWindow();
}

private void start()
{
    showWindow();
}

private void end()
{
    hideWindow();
    resetGrid();
}

private void toggleStart()
{
    if (active) end();
    else start();
}

private void quit()
{
    import core.sys.windows.windows : PostQuitMessage;

    PostQuitMessage(0);
}

void restart()
{
    import core.sys.windows.windows : GetModuleFileName;
    import std.process : spawnProcess;
    import std.conv : to;
    import core.runtime : Runtime;

    spawnProcess(Runtime.args);

    quit();
}

private LONG getCutMoveValue(Direction direction, string arg)
{
    import std.algorithm : canFind;
    import std.conv : to;

    if (arg == "0")
    {
        return 0;
    }

    auto original = (direction == Direction.up || direction == Direction.down) ? grid.rect.height : grid.rect.width;

    if (arg == "1")
    {
        return original;
    }
    else if (arg.canFind('.'))
    {
        return cast(LONG)(arg.to!double * original);
    }
    else
    {
        return arg.to!LONG;
    }
}

private void cut(Direction direction, string arg)
{
    import core.sys.windows.windows : RECT;

    if (!active) return;

    auto value = getCutMoveValue(direction, arg != null ? arg : "0.5");
    auto diff = (direction == Direction.up || direction == Direction.down) ? grid.rect.height - value : grid.rect.width - value;

    Grid newGrid = grid;
    final switch (direction) with (Direction)
    {
        case up:
            newGrid.rect.bottom -= diff;
            if (newGrid.rect.bottom < 0) newGrid.rect.bottom = 0;
            break;
        case down:
            newGrid.rect.top += diff;
            if (newGrid.rect.top < 0) newGrid.rect.top = 0;
            break;
        case left:
            newGrid.rect.right -= diff;
            if (newGrid.rect.right < 0) newGrid.rect.right = 0;
            break;
        case right:
            newGrid.rect.left += diff;
            if (newGrid.rect.left < 0) newGrid.rect.left = 0;
            break;
    }

    grid = newGrid;
    redrawWindow();

    if (newGrid.rect.height < 2 || newGrid.rect.width < 2)
    {
        resetGrid();
        hideWindow();
    }
}

private void move(Direction direction, string arg)
{
    import core.sys.windows.windows : RECT;

    if (!active) return;

    auto value = getCutMoveValue(direction, arg != null ? arg : "1");

    Grid newGrid = grid;
    final switch (direction) with (Direction)
    {
        case up:
            newGrid.rect.top -= value;
            newGrid.rect.bottom -= value;
            if (newGrid.rect.top < 0)
            {
                newGrid.rect.bottom -= newGrid.rect.top;
                newGrid.rect.top = 0;
            }
            break;
        case down:
            newGrid.rect.top += value;
            newGrid.rect.bottom += value;
            if (newGrid.rect.bottom > screenHeight)
            {
                newGrid.rect.top -= (newGrid.rect.bottom - screenHeight);
                newGrid.rect.bottom = screenHeight;
            }
            break;
        case left:
            newGrid.rect.left -= value;
            newGrid.rect.right -= value;
            if (newGrid.rect.left < 0)
            {
                newGrid.rect.right -= newGrid.rect.left;
                newGrid.rect.left = 0;
            }
            break;
        case right:
            newGrid.rect.left += value;
            newGrid.rect.right += value;
            if (newGrid.rect.right > screenWidth)
            {
                newGrid.rect.left -= (newGrid.rect.right - screenWidth);
                newGrid.rect.right = screenWidth;
            }
            break;
    }

    grid = newGrid;

    redrawWindow();
}

private void warp()
{
    import core.sys.windows.windows : SetCursorPos;
    import core.sys.windows.winuser;

    if (!active) return;

    auto middleX = grid.rect.left + grid.rect.width / 2;
    auto middleY = grid.rect.top + grid.rect.height / 2;

    INPUT input;
    input.type = INPUT_MOUSE;
    input.mi.dx = middleX * 65536 / screenWidth;
    input.mi.dy = middleY * 65536 / screenHeight;
    input.mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | draggingFlag;
    SendInput(1, &input, INPUT.sizeof);
}

private void cursorZoom(int width, int height)
{
    import core.sys.windows.windows : RECT, POINT, GetCursorPos;

    POINT cursorPosition;

    auto result = GetCursorPos(&cursorPosition);
    assert(result);

    Grid newGrid = grid;
    newGrid.rect.left = cursorPosition.x - width / 2;
    newGrid.rect.right = cursorPosition.x + width / 2;
    newGrid.rect.top = cursorPosition.y - height / 2;
    newGrid.rect.bottom = cursorPosition.y + height / 2;
    grid = newGrid;

    redrawWindow();
}

private void windowZoom()
{
    import core.sys.windows.windows : RECT, GetForegroundWindow, GetWindowRect;

    Grid newGrid = grid;
    GetWindowRect(GetForegroundWindow(), &newGrid.rect);
    grid = newGrid;

    redrawWindow();
}

private void click(string button)
{
    import core.sys.windows.winuser;

    INPUT[2] inputs;

    inputs[0].type = INPUT_MOUSE;
    inputs[1].type = INPUT_MOUSE;

    switch (button)
    {
        case "1":
            inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
            inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
            break;
        case "2":
            inputs[0].mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
            inputs[1].mi.dwFlags = MOUSEEVENTF_RIGHTUP;
            break;
        case "3":
            inputs[0].mi.dwFlags = MOUSEEVENTF_MIDDLEDOWN;
            inputs[1].mi.dwFlags = MOUSEEVENTF_MIDDLEUP;
            break;
        default:
            showError("Invalid mouse button: " ~ button);
            break;
    }

    SendInput(2, inputs.ptr, INPUT.sizeof);
}

private void doubleClick(string button)
{
    import core.sys.windows.winuser;

    INPUT[4] inputs;

    inputs[0].type = INPUT_MOUSE;
    inputs[1].type = INPUT_MOUSE;

    switch (button)
    {
        case "1":
            inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
            inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
            break;
        case "2":
            inputs[0].mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
            inputs[1].mi.dwFlags = MOUSEEVENTF_RIGHTUP;
            break;
        case "3":
            inputs[0].mi.dwFlags = MOUSEEVENTF_MIDDLEDOWN;
            inputs[1].mi.dwFlags = MOUSEEVENTF_MIDDLEUP;
            break;
        default:
            showError("Invalid mouse button: " ~ button);
            break;
    }

    inputs[2] = inputs[0];
    inputs[3] = inputs[1];

    SendInput(4, inputs.ptr, INPUT.sizeof);
}

private void drag(string button, string modifiers)
{
    import core.sys.windows.windows;
    import std.string : split;

    static bool dragging = false;

    INPUT mouseInput;

    mouseInput.type = INPUT_MOUSE;

    switch (button)
    {
        case "1":
            mouseInput.mi.dwFlags = !draggingFlag ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
            break;
        case "2":
            mouseInput.mi.dwFlags = !draggingFlag ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
            break;
        case "3":
            mouseInput.mi.dwFlags = !draggingFlag ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
            break;
        default:
            showError("Invalid mouse button: " ~ button);
            break;
    }

    if (draggingFlag && modifiers != null)
    {
        INPUT[] keyUpInputs;
        INPUT[] keyDownInputs;

        foreach (modifier; modifiers.split('+'))
        {
            INPUT keyboardInput;
            keyboardInput.type = INPUT_KEYBOARD;
            switch (modifier)
            {
                case "ctrl":
                    keyboardInput.ki.wVk = VK_CONTROL;
                    break;
                case "shift":
                    keyboardInput.ki.wVk = VK_SHIFT;
                    break;
                case "alt":
                    keyboardInput.ki.wVk = VK_MENU;
                    break;
                case "super":
                    keyboardInput.ki.wVk = VK_LWIN;
                    break;
                default:
                    break;
            }

            keyUpInputs ~= keyboardInput;

            keyboardInput.ki.dwFlags = KEYEVENTF_KEYUP;
            keyDownInputs ~= keyboardInput;
        }

        INPUT[] inputs = keyUpInputs ~ [mouseInput] ~ keyDownInputs;
        SendInput(cast(DWORD) inputs.length, inputs.ptr, INPUT.sizeof);
    }
    else
    {
        SendInput(1, &mouseInput, INPUT.sizeof);
    }

    draggingFlag = !draggingFlag ? mouseInput.mi.dwFlags : 0;
}

private void runShellCommand(string shellCommand)
{
    import std.process : spawnShell;

    spawnShell(shellCommand);
}

void loadAllConfigs()
{
    recordings = [];

    foreach (path; configFilePaths)
    {
        loadConfig(path, true);
    }

    loadRecordings();
}

void loadConfig(string pathString, bool silent = false)
{
    import std.file : exists, readText;
    import std.range : array;
    import std.conv : to;
    import std.format : format;
    import std.array : replace, split;

    string path = pathString.expandPath;

    if (!path.exists)
    {
        if (!silent)
        {
            if (path == pathString)
            {
                showError(format!"Error loading config file: %s does not exist"(path));
            }
            else
            {
                showError(format!"Error loading config file: %s (expanded to: %s) does not exist"(pathString, path));
            }
        }
        return;
    }

    foreach (line; path.readText.replace('\r', "").split('\n'))
    {
        registerKeyBinding(line.to!string);
    }
}

private void historyBack()
{
    tryPopGrid();

    redrawWindow();
}

private void changeGrid(string columnsAndRows)
{
    import std.range : split, array;
    import std.algorithm : map;
    import std.conv : to;

    auto dimArray = columnsAndRows.split('x').map!(to!int).array;

    Grid newGrid = grid;
    newGrid.columns = dimArray[0];
    newGrid.rows = dimArray[1];
    grid = newGrid;

    redrawWindow();
}

private void cellSelect(string columnsAndRows)
{
    import core.sys.windows.windows : RECT;
    import std.range : split, array;
    import std.algorithm : map;
    import std.conv : to;

    auto dimArray = columnsAndRows.split('x').map!(to!int).array;

    auto x = grid.rect.left;
    auto y = grid.rect.top;
    auto width = grid.rect.width / grid.columns;
    auto height = grid.rect.height / grid.rows;

    Grid newGrid = grid;
    newGrid.rect = RECT(x + (dimArray[0] - 1) * width, y + (dimArray[1] - 1) * height, x + dimArray[0] * width, y + dimArray[1] * height);
    if (newGrid.rect.height < 2 || newGrid.rect.width < 2)
    {
        resetGrid();
        hideWindow();
    }
    else
    {
        grid = newGrid;
        redrawWindow();
    }
}

private void record(string path = null)
{
    if (recordingActive)
    {
        stopRecording();
    }
    else
    {
        startRecording(path);
    }
}

private void replay()
{
    startReplaying();
}

private void clear()
{
    startKeyBindings = [];
    regularKeyBindings = [];
}

void processCommands(string[][] commands)
{
    foreach (command; commands)
    {
        processCommand(command);
    }
}

bool verifyCommands(string[][] commands)
{
    auto allCorrect = true;
    foreach (command; commands)
    {
        if (!verifyCommand(command))
        {
            allCorrect = false;
        }
    }
    return allCorrect;
}

void processCommand(string[] command)
{
    import std.conv : to;

    switch (command[0])
    {
        case "start":
            start();
            break;
        case "end":
            end();
            break;
        case "toggle-start":
            toggleStart();
            break;
        case "quit":
            quit();
            break;
        case "restart":
            restart();
            break;
        case "ignore":
            break;
        case "warp":
            warp();
            break;
        case "windowzoom":
            windowZoom();
            break;
        case "click":
            click(command[1]);
            break;
        case "doubleclick":
            doubleClick(command[1]);
            break;
        case "drag":
            drag(command[1], command.length == 3 ? command[2] : null);
            break;
        case "cursorzoom":
            cursorZoom(command[1].to!int, command[2].to!int);
            break;
        case "history-back":
            historyBack();
            break;
        case "grid":
            changeGrid(command[1]);
            break;
        case "cell-select":
            cellSelect(command[1]);
            break;
        case "cut-up":
        case "cut-down":
        case "cut-left":
        case "cut-right":
            cut(command[0].commandToDirection(), command.length == 2 ? command[1] : null);
            break;
        case "move-up":
        case "move-down":
        case "move-left":
        case "move-right":
            move(command[0].commandToDirection(), command.length == 2 ? command[1] : null);
            break;
        case "sh":
            runShellCommand(command[1]);
            break;
        case "loadconfig":
            loadConfig(command[1]);
            break;
        case "record":
            record(command.length == 2 ? command[1] : null);
            break;
        case "playback":
            replay();
            break;
        case "daemonize":
            //we ignore this as we always add a notification icon
            break;
        case "clear":
            clear();
            break;
        default:
            showError("Command not implemented: " ~ command[0]);
            break;
    }
}

bool verifyCommand(string[] command)
{
    //TODO: More command verification (arg types etc.)
    //TODO: Refactor (with UDAs?)

    import std.format : format;
    import std.string : join;

    auto commandString = command.join(' ');
    bool argCount(int minCount, int maxCount)
    {
        auto count = command.length - 1;
        if (count >= minCount && count <= maxCount)
        {
            return true;
        }
        
        if (minCount == maxCount)
        {
            showError(format!"Command '%s' needs %d %s but %d %s given: %s"(command[0],
                                                                            minCount,
                                                                            minCount == 1 ? "arg" : "args",
                                                                            count,
                                                                            count == 1 ? "was" : "were",
                                                                            commandString));
        }
        else
        {
            showError(format!"Command '%s' needs %d~%d %s but %d %s given: %s"(command[0],
                                                                               minCount,
                                                                               maxCount,
                                                                               maxCount == 1 ? "arg" : "args",
                                                                               count,
                                                                               count == 1 ? "was" : "were",
                                                                               commandString));
        }
        return false;
    }

    switch (command[0])
    {
        case "start":
        case "end":
        case "toggle-start":
        case "warp":
        case "windowzoom":
        case "history-back":
        case "quit":
        case "restart":
            if (!argCount(0, 0)) return false;
            break;
        case "cut-up":
        case "cut-down":
        case "cut-left":
        case "cut-right":
            if (!argCount(0, 1)) return false;
            break;
        case "move-up":
        case "move-down":
        case "move-left":
        case "move-right":
            if (!argCount(0, 1)) return false;
            break;
        case "click":
        case "doubleclick":
            if (!argCount(1, 1)) return false;
            break;
        case "drag":
            if (!argCount(1, 2)) return false;
            break;
        case "cursorzoom":
            if (!argCount(2, 2)) return false;
            break;
        case "grid":
            if (!argCount(1, 1)) return false;
            break;
        case "cell-select":
            if (!argCount(1, 1)) return false;
            break;
        case "sh":
            if (!argCount(1, 1)) return false;
            break;
        case "loadconfig":
            if (!argCount(1, 1)) return false;
            break;
        case "daemonize":
            if (!argCount(0, 0)) return false;
            break;
        case "clear":
            if (!argCount(0, 0)) return false;
            break;
        case "record":
            if (!argCount(0, 1)) return false;
            break;
        case "playback":
            if (!argCount(0, 0)) return false;
            break;
        case "grid-nav":
            if (!argCount(1, 1)) return false;
            break;
        case "ignore":
            break;
        default:
            showError("Unknown command: " ~ command[0]);
            return false;
    }
    return true;
}