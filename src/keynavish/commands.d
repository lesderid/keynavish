module keynavish.commands;

import std.typecons : BitFlags;
import keynavish;
import keynavish.types;
import keynavish.platform;

long delayMilliseconds = 0;

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

private void start()
{
    resetGrid();
    if (gridNavEnabled)
    {
        resetGridNavSelection();
    }

    version (Windows)
    {
        moveOverlayToVirtualScreen();
    }

    showWindow();

    debugLog("start: grid %dx%d at (%d,%d)-(%d,%d), %d overlay window(s)",
             grid.columns, grid.rows,
             grid.rect.left, grid.rect.top, grid.rect.right, grid.rect.bottom,
             overlayWindowCount);
}

private void end()
{
    debugLog("end");

    hideWindow();
}

private void toggleStart()
{
    if (active) end();
    else start();
}

private void quit()
{
    quitApplication();
}

void restart()
{
    import std.process : spawnProcess;
    import core.runtime : Runtime;

    version (Windows)
    {
        spawnProcess(Runtime.args);
    }
    else
    {
        import core.stdc.string : strlen;
        import keynavish.platform.macos.shim : knv_bundle_path;

        // Re-exec the bundle rather than the inner binary, so the relaunched
        // process keeps its bundle identity -- and with it the Accessibility
        // grant, which is keyed on bundle id plus signature (§7.2).
        auto bundle = knv_bundle_path();
        if (bundle !is null)
        {
            spawnProcess(["open", "-n", bundle[0 .. strlen(bundle)].idup]);
        }
        else
        {
            spawnProcess(Runtime.args);
        }
    }

    quit();
}

private int getCutMoveValue(Direction direction, string arg)
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
        return cast(int)(arg.to!double * original);
    }
    else
    {
        return arg.to!int;
    }
}

private void cut(Direction direction, string arg)
{
    if (!active) return;

    auto value = getCutMoveValue(direction, arg != null ? arg : "0.5");
    auto diff = (direction == Direction.up || direction == Direction.down) ? grid.rect.height - value : grid.rect.width - value;

    auto virtualScreen = virtualScreenRectangle;

    Grid newGrid = grid;
    final switch (direction) with (Direction)
    {
        case up:
            newGrid.rect.bottom -= diff;
            if (newGrid.rect.bottom < virtualScreen.top) newGrid.rect.bottom = virtualScreen.top;
            break;
        case down:
            newGrid.rect.top += diff;
            if (newGrid.rect.top < virtualScreen.top) newGrid.rect.top = virtualScreen.top;
            break;
        case left:
            newGrid.rect.right -= diff;
            if (newGrid.rect.right < virtualScreen.left) newGrid.rect.right = virtualScreen.left;
            break;
        case right:
            newGrid.rect.left += diff;
            if (newGrid.rect.left < virtualScreen.left) newGrid.rect.left = virtualScreen.left;
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
    if (!active) return;

    auto virtualScreen = virtualScreenRectangle;
    auto virtualScreenRight = virtualScreen.right;
    auto virtualScreenBottom = virtualScreen.bottom;

    auto value = getCutMoveValue(direction, arg != null ? arg : "1");

    Grid newGrid = grid;
    final switch (direction) with (Direction)
    {
        case up:
            newGrid.rect.top -= value;
            newGrid.rect.bottom -= value;
            if (newGrid.rect.top < virtualScreen.top)
            {
                newGrid.rect.bottom -= (newGrid.rect.top - virtualScreen.top);
                newGrid.rect.top = virtualScreen.top;
            }
            break;
        case down:
            newGrid.rect.top += value;
            newGrid.rect.bottom += value;
            if (newGrid.rect.bottom > virtualScreenBottom)
            {
                newGrid.rect.top -= (newGrid.rect.bottom - virtualScreenBottom);
                newGrid.rect.bottom = virtualScreenBottom;
            }
            break;
        case left:
            newGrid.rect.left -= value;
            newGrid.rect.right -= value;
            if (newGrid.rect.left < virtualScreen.left)
            {
                newGrid.rect.right -= (newGrid.rect.left - virtualScreen.left);
                newGrid.rect.left = virtualScreen.left;
            }
            break;
        case right:
            newGrid.rect.left += value;
            newGrid.rect.right += value;
            if (newGrid.rect.right > virtualScreenRight)
            {
                newGrid.rect.left -= (newGrid.rect.right - virtualScreenRight);
                newGrid.rect.right = virtualScreenRight;
            }
            break;
    }

    grid = newGrid;

    redrawWindow();
}

private void warp()
{
    if (!active) return;

    warpCursor(Point(grid.rect.left + grid.rect.width / 2,
                     grid.rect.top + grid.rect.height / 2));
}

private void cursorZoom(int width, int height)
{
    auto cursor = cursorPosition;

    Grid newGrid = grid;
    newGrid.rect.left = cursor.x - width / 2;
    newGrid.rect.right = cursor.x + width / 2;
    newGrid.rect.top = cursor.y - height / 2;
    newGrid.rect.bottom = cursor.y + height / 2;
    grid = newGrid;

    redrawWindow();
}

private void windowZoom()
{
    auto rect = focusedWindowRect();

    if (rect.isNull) return;

    Grid newGrid = grid;
    newGrid.rect = rect.get();
    grid = newGrid;

    redrawWindow();
}

private void click(string button)
{
    import std.conv : to;

    auto buttonNumber = button.toButtonNumber;
    if (buttonNumber == 0)
    {
        showError("Invalid mouse button: " ~ button);
        return;
    }

    mouseClick(buttonNumber, delayMilliseconds);
}

private void doubleClick(string button)
{
    auto buttonNumber = button.toButtonNumber;
    if (buttonNumber == 0 || buttonNumber > 3)
    {
        showError("Invalid mouse button: " ~ button);
        return;
    }

    mouseDoubleClick(buttonNumber, delayMilliseconds);
}

private void drag(string button, string modifiers)
{
    import std.string : split;

    auto buttonNumber = button.toButtonNumber;
    if (buttonNumber == 0 || buttonNumber > 3)
    {
        showError("Invalid mouse button: " ~ button);
        return;
    }

    BitFlags!ModifierKey modifierFlags = ModifierKey.none;

    if (modifiers != null)
    {
        foreach (modifier; modifiers.split('+'))
        {
            switch (modifier)
            {
                case "ctrl":  modifierFlags |= ModifierKey.ctrl; break;
                case "shift": modifierFlags |= ModifierKey.shift; break;
                case "alt":   modifierFlags |= ModifierKey.alt; break;
                case "super": modifierFlags |= ModifierKey.super_; break;
                default: break;
            }
        }
    }

    mouseDragToggle(buttonNumber, modifierFlags);
}

private int toButtonNumber(string button)
{
    switch (button)
    {
        case "1": return 1;
        case "2": return 2;
        case "3": return 3;
        case "4": return 4;
        case "5": return 5;
        default:  return 0;
    }
}

private void runShellCommand(string shellCommand)
{
    import std.process : spawnShell;

    spawnShell(shellCommand);
}

void loadAllConfigs()
{
    recordings = [];

    foreach (path; portableConfigPaths ~ configFilePaths)
    {
        loadConfig(path, true);
    }

    version (Windows)
    {
        loadRecordings();
    }
    else
    {
        // Recordings are deferred on macOS (§6.3), so the files are not read at
        // all. Parsing them anyway would be worse than useless: an existing
        // ~/.keynav_macros written on Windows holds Windows keycodes that mean
        // nothing here, and loadRecordings warns on duplicates -- so a shared
        // macros file could raise alerts at startup for a feature that does
        // nothing. That contradicts the promise that deferred commands are
        // simply inert.
    }
}

/// Drops every binding and rebuilds it from the defaults plus the config files.
///
/// Used on macOS when the keyboard layout changes: key names resolve to
/// keycodes at registration time, so the existing bindings would otherwise keep
/// pointing at the previous layout's physical keys (§6.3).
void reloadAllKeyBindings()
{
    clear();

    registerDefaultKeyBindings();

    loadAllConfigs();
}

/// Config shipped alongside the program, loaded before the user's ~ files.
private string[] portableConfigPaths()
{
    version (Windows)
    {
        import std.file : thisExePath;
        import std.path : dirName, buildPath;

        return [dirName(thisExePath()).buildPath("keynavrc")];
    }
    else
    {
        // Inside the bundle, next to the executable is Contents/MacOS, which is
        // not a place a user would ever look; the shipped default lives in
        // Contents/Resources instead. See MACOS-PORT.md §6.11.
        import core.stdc.string : strlen;
        import std.path : buildPath;
        import keynavish.platform.macos.shim : knv_resource_path;

        auto resources = knv_resource_path();
        if (resources is null) return [];

        return [resources[0 .. strlen(resources)].idup.buildPath("keynavrc")];
    }
}

void loadConfig(string pathString, bool silent = false)
{
    import std.file : exists, readText;
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

private void setGridNav(string value)
{
    import std.string : toLower;

    switch (value.toLower)
    {
        case "on":
            enableGridNav(true);
            break;
        case "off":
            enableGridNav(false);
            break;
        case "toggle":
            enableGridNav(!gridNavEnabled);
            break;
        default:
            showError("Invalid grid-nav value: " ~ value);
            return;
    }

    redrawWindow();
}

void cellSelect(string columnsAndRows)
{
    import std.range : split, array;
    import std.algorithm : map;
    import std.conv : to;

    auto dimArray = columnsAndRows.split('x').map!(to!int).array;

    auto x = grid.rect.left;
    auto y = grid.rect.top;
    auto width = grid.rect.width / grid.columns;
    auto height = grid.rect.height / grid.rows;

    Grid newGrid = grid;
    newGrid.rect = Rect(x + (dimArray[0] - 1) * width, y + (dimArray[1] - 1) * height, x + dimArray[0] * width, y + dimArray[1] * height);
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
    version (Windows)
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
    else
    {
        // Recordings are deferred on macOS (MACOS-PORT.md §6.3). This must stay
        // silent rather than erroring: `q record ~/.keynav_macros` is in the
        // stock keybindings, so a shared keynavrc would otherwise raise a dialog
        // on an ordinary keystroke.
    }
}

private void replay()
{
    version (Windows)
    {
        startReplaying();
    }
    else
    {
        // See record(), above.
    }
}

private void clear()
{
    startKeyBindings = [];
    regularKeyBindings = [];
    delayMilliseconds = 0;
}

private void setDelay(string delayString)
{
    import std.conv : to;

    delayMilliseconds = delayString.to!long;
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
        case "grid-nav":
            setGridNav(command[1]);
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
        case "x-set-delay":
            setDelay(command[1]);
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
        case "x-set-delay":
            if (!argCount(1, 1)) return false;
            break;
        default:
            showError("Unknown command: " ~ command[0]);
            return false;
    }
    return true;
}
