module keynavish.commands;

import keynavish;

import core.sys.windows.windows : LONG, DWORD;

@system nothrow:

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
    import core.sys.windows.windows : ExitProcess;

    ExitProcess(0);
}

private void restart()
{
    import core.sys.windows.windows : GetModuleFileName;
    import std.process : spawnProcess;
    import std.conv : to;
    import std.exception : assumeWontThrow;

    wchar[0x7FFF] path;
    assert(GetModuleFileName(null, path.ptr, path.length));

    spawnProcess(path.to!string).assumeWontThrow;

    quit();
}

private LONG getCutMoveValue(Direction direction, string arg)
{
    import std.algorithm : canFind;
    import std.conv : to;
    import std.exception : assumeWontThrow;

    if (arg == "0")
    {
        return 0;
    }

    auto original = (direction == Direction.up || direction == Direction.down) ? gridRect.height : gridRect.width;

    if (arg == "1")
    {
        return original;
    }
    else if (arg.canFind('.').assumeWontThrow)
    {
        return cast(LONG)(arg.to!double * original).assumeWontThrow;
    }
    else
    {
        return arg.to!LONG.assumeWontThrow;
    }
}

private void cut(Direction direction, string arg)
{
    import core.sys.windows.windows : RECT;

    if (!active) return;

    auto value = getCutMoveValue(direction, arg != null ? arg : "0.5");
    auto diff = (direction == Direction.up || direction == Direction.down) ? gridRect.height - value : gridRect.width - value;

    RECT newRect = gridRect;
    final switch (direction) with (Direction)
    {
        case up:
            newRect.bottom -= diff;
            if (newRect.bottom < 0) newRect.bottom = 0;
            break;
        case down:
            newRect.top += diff;
            if (newRect.top < 0) newRect.top = 0;
            break;
        case left:
            newRect.right -= diff;
            if (newRect.right < 0) newRect.right = 0;
            break;
        case right:
            newRect.left += diff;
            if (newRect.left < 0) newRect.left = 0;
            break;
    }

    gridRect = newRect;
    redrawWindow();

    if (newRect.height < 2 || newRect.width < 2)
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

    RECT newRect = gridRect;
    final switch (direction) with (Direction)
    {
        case up:
            newRect.top -= value;
            newRect.bottom -= value;
            if (newRect.top < 0)
            {
                newRect.bottom -= newRect.top;
                newRect.top = 0;
            }
            break;
        case down:
            newRect.top += value;
            newRect.bottom += value;
            if (newRect.bottom > screenHeight)
            {
                newRect.top -= (newRect.bottom - screenHeight);
                newRect.bottom = screenHeight;
            }
            break;
        case left:
            newRect.left -= value;
            newRect.right -= value;
            if (newRect.left < 0)
            {
                newRect.right -= newRect.left;
                newRect.left = 0;
            }
            break;
        case right:
            newRect.left += value;
            newRect.right += value;
            if (newRect.right > screenWidth)
            {
                newRect.left -= (newRect.right - screenWidth);
                newRect.right = screenWidth;
            }
            break;
    }

    gridRect = newRect;

    redrawWindow();
}

private void warp()
{
    import core.sys.windows.windows : SetCursorPos;
    import core.sys.windows.winuser;

    if (!active) return;

    auto middleX = gridRect.left + gridRect.width / 2;
    auto middleY = gridRect.top + gridRect.height / 2;

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

    assert(GetCursorPos(&cursorPosition));

    RECT newRect;
    newRect.left = cursorPosition.x - width / 2;
    newRect.right = cursorPosition.x + width / 2;
    newRect.top = cursorPosition.y - height / 2;
    newRect.bottom = cursorPosition.y + height / 2;
    gridRect = newRect;

    redrawWindow();
}

private void windowZoom()
{
    import core.sys.windows.windows : RECT, GetForegroundWindow, GetWindowRect;

    RECT newRect;
    GetWindowRect(GetForegroundWindow(), &newRect);
    gridRect = newRect;

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
    //TODO: Implement modifiers

    import core.sys.windows.windows;
    import std.string : split;
    import std.exception : assumeWontThrow;

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

        foreach (modifier; modifiers.split('+').assumeWontThrow)
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
    import std.exception : assumeWontThrow;

    spawnShell(shellCommand).assumeWontThrow;
}

private void historyBack()
{
    tryPopGridRect();

    redrawWindow();
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
    import std.exception : assumeWontThrow;

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
            cursorZoom(command[1].to!int.assumeWontThrow, command[2].to!int.assumeWontThrow);
            break;
        case "history-back":
            historyBack();
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
        default:
            showError("Command not implemented: " ~ command[0]);
            break;
    }
}

bool verifyCommand(string[] command)
{
    //TODO: More command verification (arg types etc.)

    import std.format : format;
    import std.exception : assumeWontThrow;
    import std.string : join;

    auto commandString = command.join(' ').assumeWontThrow;
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
                                                                            commandString).assumeWontThrow);
        }
        else
        {
            showError(format!"Command '%s' needs %d~%d %s but %d %s given: %s"(command[0],
                                                                               minCount,
                                                                               maxCount,
                                                                               maxCount == 1 ? "arg" : "args",
                                                                               count,
                                                                               count == 1 ? "was" : "were",
                                                                               commandString).assumeWontThrow);
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
        case "sh":
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