module keynavish.keyboardinput;

import std.typecons : Nullable, BitFlags;
import keynavish;
import keynavish.types;
import keynavish.platform;

static this()
{
    registerDefaultKeyBindings();
}

//
// The keynav default bindings, applied before any config file is read.
//
// Callable rather than inlined into the module constructor because the macOS
// build re-runs it when the keyboard layout changes: bindings store resolved
// keycodes, so they have to be resolved again against the new layout (§6.3).
//
void registerDefaultKeyBindings()
{
    registerKeyBinding("clear");
    registerKeyBinding("ctrl+semicolon start");
    registerKeyBinding("Escape end");
    registerKeyBinding("ctrl+bracketleft end");
    registerKeyBinding("q record ~/.keynav_macros");
    registerKeyBinding("shift+at playback");
    registerKeyBinding("a history-back");
    registerKeyBinding("h cut-left");
    registerKeyBinding("j cut-down");
    registerKeyBinding("k cut-up");
    registerKeyBinding("l cut-right");
    registerKeyBinding("shift+h move-left");
    registerKeyBinding("shift+j move-down");
    registerKeyBinding("shift+k move-up");
    registerKeyBinding("shift+l move-right");
    registerKeyBinding("space warp,click 1,end");
    registerKeyBinding("Return warp,click 1,end");
    registerKeyBinding("semicolon warp,end");
    registerKeyBinding("w warp");
    registerKeyBinding("t windowzoom");
    registerKeyBinding("c cursorzoom 300 300");
    registerKeyBinding("e end");
    registerKeyBinding("1 click 1");
    registerKeyBinding("2 click 2");
    registerKeyBinding("3 click 3");
    registerKeyBinding("ctrl+h cut-left");
    registerKeyBinding("ctrl+j cut-down");
    registerKeyBinding("ctrl+k cut-up");
    registerKeyBinding("ctrl+l cut-right");
    registerKeyBinding("y cut-left,cut-up");
    registerKeyBinding("u cut-right,cut-up");
    registerKeyBinding("b cut-left,cut-down");
    registerKeyBinding("n cut-right,cut-down");
    registerKeyBinding("shift+y move-left,move-up");
    registerKeyBinding("shift+u move-right,move-up");
    registerKeyBinding("shift+b move-left,move-down");
    registerKeyBinding("shift+n move-right,move-down");
    registerKeyBinding("ctrl+y cut-left,cut-up");
    registerKeyBinding("ctrl+u cut-right,cut-up");
    registerKeyBinding("ctrl+b cut-left,cut-down");
    registerKeyBinding("ctrl+n cut-right,cut-down");
}

struct KeyCombination
{
    KeyCode keyCode;
    BitFlags!ModifierKey modifiers;
}

struct KeyBinding
{
    KeyCombination keyCombination;
    string[][] commands;
}

KeyBinding[] regularKeyBindings;
KeyBinding[] startKeyBindings;

Nullable!KeyBinding parseKeyBindingString(string bindingString)
{
    import std.algorithm : findSplit, map, until, startsWith;
    import std.array : array;
    import std.format : format;
    import std.conv : to;
    import std.string : strip, split;

    //strip comments, whitespace, and stop if string is empty
    bindingString = bindingString.until('#').to!string.strip;
    if (bindingString.length == 0)
    {
        return typeof(return)();
    }

    if (bindingString.startsWith("daemonize", "clear", "loadconfig", "x-set-delay"))
    {
        auto command = bindingString.parseCommaDelimitedCommands()[0];
        verifyCommand(command) && processCommand(command);
        return typeof(return)();
    }

    auto parts = bindingString.findSplit(" ");

    string[] keyStrings = parts[0].split('+');

    string[][] commands = parts[2].parseCommaDelimitedCommands();

    auto keyCombination = keyStrings.parseKeyCombination();
    if (!verifyCommands(commands) || keyCombination.isNull)
    {
        return typeof(return)();
    }

    return typeof(return)(KeyBinding(keyCombination.get(), commands));
}

Nullable!KeyCombination parseKeyCombination(string[] keyStrings)
{
    KeyCombination combination;
    bool keyCodeSet;

    foreach (keyString; keyStrings)
    {
        bool setKeyCode(KeyCode keyCode)
        {
            if (keyCodeSet)
            {
                showError("More than one non-modifier key given: " ~ keyString);
                return false;
            }
            combination.keyCode = keyCode;
            keyCodeSet = true;
            return true;
        }

        switch (keyString)
        {
            case "ctrl":
                combination.modifiers |= ModifierKey.ctrl;
                continue;
            case "alt":
                combination.modifiers |= ModifierKey.alt;
                continue;
            case "shift":
                combination.modifiers |= ModifierKey.shift;
                continue;
            case "super":
                combination.modifiers |= ModifierKey.super_;
                continue;
            default:
                break;
        }

        auto resolved = resolveKeyName(keyString);
        if (resolved.isNull)
        {
            showError("Unknown key: " ~ keyString);
            return typeof(return)();
        }

        if (!setKeyCode(resolved.get())) return typeof(return)();
    }

    return typeof(return)(combination);
}

bool registerKeyBinding(string bindingString)
{
    import std.algorithm : find;
    import std.range : empty;

    auto nullableKeyBinding = bindingString.parseKeyBindingString();
    if (nullableKeyBinding.isNull)
    {
        return false;
    }
    auto keyBinding = nullableKeyBinding.get();

    if (keyBinding.commands[0][0] == "start")
    {
        startKeyBindings ~= keyBinding;
    }
    else
    {
        auto originalBinding = regularKeyBindings.find!(b => b.keyCombination == keyBinding.keyCombination);
        if (!originalBinding.empty)
        {
            originalBinding[0] = keyBinding;
        }
        else
        {
            regularKeyBindings ~= keyBinding;
        }

        if (keyBinding.commands[0][0] == "toggle-start")
        {
            startKeyBindings ~= keyBinding;
        }
    }

    return true;
}

private bool handleGridNavKey(KeyCode keyCode, BitFlags!ModifierKey modifiers)
{
    import std.conv : to;

    if (!gridNavEnabled)
    {
        return false;
    }

    if (isEscapeKey(keyCode))
    {
        enableGridNav(false);
        redrawWindow();
        return true;
    }

    if (modifiers)
    {
        return false;
    }

    auto character = characterForKeyCode(keyCode);
    if (character < 'a' || character > 'z')
    {
        return false;
    }

    auto value = cast(int)(character - 'a');

    if (gridNavState == GridNavState.row)
    {
        if (value >= grid.rows)
        {
            return false;
        }

        gridNavRow = value;
        gridNavState = GridNavState.column;
        redrawWindow();
        return true;
    }

    if (value >= grid.columns)
    {
        return false;
    }

    gridNavColumn = value;
    cellSelect((gridNavColumn + 1).to!string ~ "x" ~ (gridNavRow + 1).to!string);
    resetGridNavSelection();
    redrawWindow();
    return true;
}

//
// The whole decision path for a key press, shared between platforms: which
// binding matches, whether grid-nav intercepts it, whether it gets recorded,
// and whether the key should be swallowed. Each platform contributes only a
// thin callback that translates its native event into (keyCode, modifiers) and
// acts on the returned "consume" flag. See MACOS-PORT.md §5.2b.
//
// Returns true when the key should be swallowed rather than passed on.
//
bool handleKeyDown(KeyCode keyCode, BitFlags!ModifierKey modifiers)
{
    import std.algorithm : find;
    import std.range : empty;

    auto pressedCombination = KeyCombination(keyCode, modifiers);

    if (!active)
    {
        auto keyBindingRange = startKeyBindings.find!(b => b.keyCombination == pressedCombination);
        if (!keyBindingRange.empty)
        {
            debugLog("start binding matched (keycode %d)", keyCode);
            processCommands(keyBindingRange[0].commands);
            return true;
        }

        return false;
    }

    if (waitingForRecordingKey)
    {
        setRecordingKey(keyCode);
    }
    else if (replaying)
    {
        replay(keyCode);
    }
    else if (handleGridNavKey(keyCode, modifiers))
    {
        return true;
    }
    else
    {
        auto keyBindingRange = regularKeyBindings.find!(b => b.keyCombination == pressedCombination);
        if (!keyBindingRange.empty)
        {
            if (recordingActive)
            {
                recordCommands(keyBindingRange[0].commands);
            }
            processCommands(keyBindingRange[0].commands);
        }
        else if (!isModifierKey(keyCode))
        {
            // Swallowed while the grid is up but matching nothing. If this fires
            // for a key the user expected to work, the grid is active when they
            // did not think it was.
            debugLog("no binding for keycode %d while active; key swallowed", keyCode);
        }
    }

    // While the grid is up every key is swallowed, so stray keystrokes don't
    // reach the application underneath -- except the modifiers themselves,
    // which must keep flowing or the OS loses track of their state.
    return !isModifierKey(keyCode);
}
