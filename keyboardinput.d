module keynavish.keyboardinput;

import core.sys.windows.windows;
import std.typecons : Nullable, BitFlags;
import keynavish;

@system nothrow:

static this()
{
    //TODO: Read keybinds from config file
    registerKeyBinding("ctrl+semicolon start #start on ctrl+;");
    registerKeyBinding("ctrl+period start #start on ctrl+. too (for other keyboard layouts)");
    registerKeyBinding("Escape end #end on esc");
    registerKeyBinding("Left cut-left");
    registerKeyBinding("Down cut-down");
    registerKeyBinding("Up cut-up");
    registerKeyBinding("Right cut-right");
    registerKeyBinding("shift+Left move-left");
    registerKeyBinding("shift+Down move-down");
    registerKeyBinding("shift+Up move-up");
    registerKeyBinding("shift+Right move-right");
    registerKeyBinding("y cut-left,cut-up");
    registerKeyBinding("space warp,click 1,end");
    registerKeyBinding("alt+space warp,click 2,end");
    registerKeyBinding("shift+space warp,click 3,end");
    registerKeyBinding("d warp,doubleclick 1,end");
    registerKeyBinding("alt+d warp,doubleclick 2,end");
    registerKeyBinding("shift+d warp,doubleclick 3,end");
    registerKeyBinding("semicolon warp,end");
    registerKeyBinding("period warp,end");
    registerKeyBinding("c cursorzoom 200 200");
    registerKeyBinding("w windowzoom");
    registerKeyBinding("super+t toggle-start");
    registerKeyBinding("q quit");
    registerKeyBinding("r restart");
    registerKeyBinding("u sh \"explorer %USERPROFILE%\"");
    registerKeyBinding("b warp,drag 1");
    registerKeyBinding("ctrl+b warp,drag 1 ctrl");
    registerKeyBinding("shift+b warp,drag 1 shift");
    registerKeyBinding("shift+ctrl+b warp,drag 1 shift+ctrl");
    registerKeyBinding("a history-back");
}

enum ModifierKey
{
    none   = 0,
    ctrl   = 1 << 0,
    shift  = 1 << 1,
    alt    = 1 << 2,
    super_ = 1 << 3,
}

struct KeyCombination
{
    DWORD vkCode;
    BitFlags!ModifierKey modifiers;
}

struct KeyBinding
{
    KeyCombination keyCombination;
    string[][] commands;
}

KeyBinding[] regularKeyBindings;
KeyBinding[] startKeyBindings;

void registerKeyboardHook()
{
    SetWindowsHookEx(WH_KEYBOARD_LL, &lowLevelKeyboardProc, GetModuleHandle(null), 0);
}

Nullable!KeyBinding parseKeyBindingString(string bindingString)
{
    import std.algorithm : findSplit, map, until;
    import std.csv : csvReader, Malformed;
    import std.array : array;
    import std.format : format;
    import std.exception : assumeWontThrow;
    import std.conv : to;
    import std.string : strip, split;

    //strip comments, whitespace, and stop if string is empty
    bindingString = bindingString.until('#').to!string.assumeWontThrow.strip;
    if (bindingString.length == 0)
    {
        return typeof(return)();
    }

    if (bindingString == "daemonize")
    {
        //we ignore this as we (will) use a system tray icon
        return typeof(return)();
    }
    else if (bindingString == "clear")
    {
        startKeyBindings = [];
        regularKeyBindings = [];

        return typeof(return)();
    }

    auto parts = bindingString.findSplit(" ");

    string[] keyStrings = parts[0].split('+').assumeWontThrow;

    //abusing csvReader so quoted strings are handled properly
    string[][] commands = parts[2].csvReader!(string, Malformed.ignore).front
                                .map!(c => c.csvReader!(string, Malformed.ignore)(' ').front.array)
                                .array.assumeWontThrow;

    auto keyCombination = keyStrings.parseKeyCombination();
    if (!verifyCommands(commands) || keyCombination.isNull)
    {
        return typeof(return)();
    }

    return typeof(return)(KeyBinding(keyCombination.get(), commands));
}

Nullable!KeyCombination parseKeyCombination(string[] keyStrings)
{
    //TODO: Refactor
    //TODO: Add more keys from X11/keysymdef.h

    KeyCombination combination;

    foreach (keyString; keyStrings)
    {
        bool setVkCode(DWORD vkCode)
        {
            if (combination.vkCode != 0)
            {
                showError("More than one non-modifier key given: " ~ keyString);
                return false;
            }
            combination.vkCode = vkCode;
            return true;
        }

        switch (keyString)
        {
            case "ctrl":
                combination.modifiers |= ModifierKey.ctrl;
                break;
            case "alt":
                combination.modifiers |= ModifierKey.alt;
                break;
            case "shift":
                combination.modifiers |= ModifierKey.shift;
                break;
            case "super":
                combination.modifiers |= ModifierKey.super_;
                break;
            case "Super_L":
                if (!setVkCode(VK_LWIN)) return typeof(return)();
                break;
            case "Super_R":
                if (!setVkCode(VK_RWIN)) return typeof(return)();
                break;
            case "semicolon":
                if (!setVkCode(VK_OEM_1)) return typeof(return)();
                break;
            case "Escape":
                if (!setVkCode(VK_ESCAPE)) return typeof(return)();
                break;
            case "Tab":
                if (!setVkCode(VK_TAB)) return typeof(return)();
                break;
            case "Left":
                if (!setVkCode(VK_LEFT)) return typeof(return)();
                break;
            case "Up":
                if (!setVkCode(VK_UP)) return typeof(return)();
                break;
            case "Right":
                if (!setVkCode(VK_RIGHT)) return typeof(return)();
                break;
            case "Down":
                if (!setVkCode(VK_DOWN)) return typeof(return)();
                break;
            case "space":
                if (!setVkCode(VK_SPACE)) return typeof(return)();
                break;
            case "period":
                if (!setVkCode(VK_OEM_PERIOD)) return typeof(return)();
                break;
            case "a":
            case "b":
            case "c":
            case "d":
            case "e":
            case "f":
            case "g":
            case "h":
            case "i":
            case "j":
            case "k":
            case "l":
            case "m":
            case "n":
            case "o":
            case "p":
            case "q":
            case "r":
            case "s":
            case "t":
            case "u":
            case "v":
            case "w":
            case "x":
            case "y":
            case "z":
                if(!setVkCode(0x41 + (keyString[0] - 'a'))) return typeof(return)();
                break;
            default:
                showError("Unknown key: " ~ keyString);
                return typeof(return)();
        }
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

extern(Windows)
LRESULT lowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam)
{
    import std.algorithm : find;
    import std.range : empty;

    auto hookStruct = cast(PKBDLLHOOKSTRUCT) lParam;

    if (nCode == HC_ACTION)
    {
        switch (wParam)
        {
            case WM_KEYDOWN:
            case WM_SYSKEYDOWN:
                BitFlags!ModifierKey modifiers = ModifierKey.none;
                modifiers |= (GetKeyState(VK_CONTROL) & 0x8000) != 0 ? ModifierKey.ctrl : ModifierKey.none;
                modifiers |= (GetKeyState(VK_SHIFT  ) & 0x8000) != 0 ? ModifierKey.shift : ModifierKey.none;
                modifiers |= (hookStruct.flags & LLKHF_ALTDOWN) != 0 ? ModifierKey.alt : ModifierKey.none;
                modifiers |= ((GetKeyState(VK_LWIN) & 0x8000) | (GetKeyState(VK_RWIN) & 0x8000)) != 0 ? ModifierKey.super_ : ModifierKey.none;

                auto pressedCombination = KeyCombination(hookStruct.vkCode, modifiers);

                if (!active)
                {
                    auto keyBindingRange = startKeyBindings.find!(b => b.keyCombination == pressedCombination);
                    if (!keyBindingRange.empty)
                    {
                        processCommands(keyBindingRange[0].commands);
                        return 1;
                    }
                    else
                    {
                        return CallNextHookEx(null, nCode, wParam, lParam);
                    }
                }
                else
                {
                    auto keyBindingRange = regularKeyBindings.find!(b => b.keyCombination == pressedCombination);
                    if (!keyBindingRange.empty)
                    {
                        processCommands(keyBindingRange[0].commands);
                    }
                    return ((hookStruct.vkCode >= VK_LSHIFT && hookStruct.vkCode <= VK_RCONTROL) || hookStruct.vkCode == VK_LWIN || hookStruct.vkCode == VK_RWIN)
                        ? CallNextHookEx(null, nCode, wParam, lParam)
                        : 1;
                }
            default:
                break;
        }
    }

    return CallNextHookEx(null, nCode, wParam, lParam);
}
