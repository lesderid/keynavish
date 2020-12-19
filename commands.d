module keynavish.commands;

import keynavish.keynavish;
import keynavish.errorhandling;
import keynavish.helpers;
import core.sys.windows.windows : LONG;

@system nothrow:

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
    if (!active) return;

    auto value = getCutMoveValue(direction, arg != null ? arg : "0.5");
    auto diff = (direction == Direction.up || direction == Direction.down) ? gridRect.height - value : gridRect.width - value;

    final switch (direction) with (Direction)
    {
        case up:
            gridRect.bottom -= diff;
            if (gridRect.bottom < 0) gridRect.bottom = 0;
            break;
        case down:
            gridRect.top += diff;
            if (gridRect.top < 0) gridRect.top = 0;
            break;
        case left:
            gridRect.right -= diff;
            if (gridRect.right < 0) gridRect.right = 0;
            break;
        case right:
            gridRect.left += diff;
            if (gridRect.left < 0) gridRect.left = 0;
            break;
    }

    redrawWindow();

    if (gridRect.height < 2 || gridRect.width < 2)
    {
        resetGrid();
        hideWindow();
    }
}

private void move(Direction direction, string arg)
{
    if (!active) return;

    auto value = getCutMoveValue(direction, arg != null ? arg : "1");

    final switch (direction) with (Direction)
    {
        case up:
            gridRect.top -= value;
            gridRect.bottom -= value;
            if (gridRect.top < 0)
            {
                gridRect.bottom -= gridRect.top;
                gridRect.top = 0;
            }
            break;
        case down:
            gridRect.top += value;
            gridRect.bottom += value;
            if (gridRect.bottom > screenHeight)
            {
                gridRect.top -= (gridRect.bottom - screenHeight);
                gridRect.bottom = screenHeight;
            }
            break;
        case left:
            gridRect.left -= value;
            gridRect.right -= value;
            if (gridRect.left < 0)
            {
                gridRect.right -= gridRect.left;
                gridRect.left = 0;
            }
            break;
        case right:
            gridRect.left += value;
            gridRect.right += value;
            if (gridRect.right > screenWidth)
            {
                gridRect.left -= (gridRect.right - screenWidth);
                gridRect.right = screenWidth;
            }
            break;
    }

    redrawWindow();
}

private void warp()
{
    import core.sys.windows.windows : SetCursorPos;

    if (!active) return;

    auto middleX = gridRect.left + gridRect.width / 2;
    auto middleY = gridRect.top + gridRect.height / 2;

    SetCursorPos(middleX, middleY);
}

private void cursorZoom(int width, int height)
{
    import core.sys.windows.windows : POINT, GetCursorPos;

    POINT cursorPosition;

    assert(GetCursorPos(&cursorPosition));

    gridRect.left = cursorPosition.x - width / 2;
    gridRect.right = cursorPosition.x + width / 2;
    gridRect.top = cursorPosition.y - height / 2;
    gridRect.bottom = cursorPosition.y + height / 2;

    redrawWindow();
}

private void windowZoom()
{
    import core.sys.windows.windows : GetForegroundWindow, GetWindowRect;

    GetWindowRect(GetForegroundWindow(), &gridRect);

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
        case "cursorzoom":
            cursorZoom(command[1].to!int.assumeWontThrow, command[2].to!int.assumeWontThrow);
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
        case "warp":
        case "windowzoom":
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
        case "cursorzoom":
            if (!argCount(2, 2)) return false;
            break;
        case "ignore":
            break;
        default:
            showError("Unknown command: " ~ command[0]);
            return false;
    }
    return true;
}