module keynavish.keyboardinput;

import core.sys.windows.windows;
import std.typecons : Nullable, BitFlags;
import keynavish;

static this()
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
    SetWindowsHookEx(WH_KEYBOARD_LL, &exceptionHandlerWrapper!lowLevelKeyboardProc, GetModuleHandle(null), 0);
}

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

    if (bindingString.startsWith("daemonize", "clear", "loadconfig"))
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
            case "Insert":
                if (!setVkCode(VK_INSERT)) return typeof(return)();
                break;
            case "Home":
                if (!setVkCode(VK_HOME)) return typeof(return)();
                break;
            case "End":
                if (!setVkCode(VK_END)) return typeof(return)();
                break;
            case "Prior":
            case "Page_Up":
                if (!setVkCode(VK_PRIOR)) return typeof(return)();
                break;
            case "Next":
            case "Page_Down":
                if (!setVkCode(VK_NEXT)) return typeof(return)();
                break;
            case "Delete":
                if (!setVkCode(VK_DELETE)) return typeof(return)();
                break;
            case "Return":
                if (!setVkCode(VK_RETURN)) return typeof(return)();
                break;
            case "space":
                if (!setVkCode(VK_SPACE)) return typeof(return)();
                break;
            case "bracketleft":
                if (!setVkCode(VK_OEM_4)) return typeof(return)();
                break;
            case "backslash":
                if (!setVkCode(VK_OEM_5)) return typeof(return)();
                break;
            case "bracketright":
                if (!setVkCode(VK_OEM_6)) return typeof(return)();
                break;
            case "at":
                //HACK: This doesn't have its own vkcode on Windows, but on X11 it has its own keysym
                if (!setVkCode('2')) return typeof(return)();
                break;
            case "plus":
                if (!setVkCode(VK_OEM_PLUS)) return typeof(return)();
                break;
            case "comma":
                if (!setVkCode(VK_OEM_COMMA)) return typeof(return)();
                break;
            case "minus":
                if (!setVkCode(VK_OEM_MINUS)) return typeof(return)();
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
                if(!setVkCode('A' + (keyString[0] - 'a'))) return typeof(return)();
                break;
            case "0":
            case "1":
            case "2":
            case "3":
            case "4":
            case "5":
            case "6":
            case "7":
            case "8":
            case "9":
                if (!setVkCode(keyString[0])) return typeof(return)();
                break;
            case "KP_0":
            case "KP_1":
            case "KP_2":
            case "KP_3":
            case "KP_4":
            case "KP_5":
            case "KP_6":
            case "KP_7":
            case "KP_8":
            case "KP_9":
                if (!setVkCode(0x60 + keyString[3] - '0')) return typeof(return)();
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
                        if (recordingActive)
                        {
                            recordCommands(keyBindingRange[0].commands);
                        }
                        processCommands(keyBindingRange[0].commands);
                    }
                    else
                    {
                        if (waitingForRecordingKey)
                        {
                            setRecordingKey(hookStruct.vkCode);
                        }
                        else if (replaying)
                        {
                            replay(hookStruct.vkCode);
                        }
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
