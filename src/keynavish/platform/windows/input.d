module keynavish.platform.windows.input;

version (Windows):

import std.typecons : BitFlags, Nullable;
import core.sys.windows.windows;
import core.sys.windows.winuser;
import keynavish;
import keynavish.types;
import keynavish.platform.windows.display;

//
// Low-level keyboard hook and SendInput-based mouse synthesis. Moved from
// keyboardinput.d and commands.d during the platform refactor; the decision
// logic now lives in the shared handleKeyDown (§5.2b), so only event
// translation remains here.
//

private DWORD draggingFlag;

// --- Keyboard ---------------------------------------------------------------

bool installKeyboardHook()
{
    return SetWindowsHookEx(WH_KEYBOARD_LL, &exceptionHandlerWrapper!lowLevelKeyboardProc,
                            GetModuleHandle(null), 0) !is null;
}

extern(Windows)
LRESULT lowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam)
{
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

                if (handleKeyDown(cast(KeyCode) hookStruct.vkCode, modifiers))
                {
                    return 1;
                }

                return CallNextHookEx(null, nCode, wParam, lParam);
            default:
                break;
        }
    }

    return CallNextHookEx(null, nCode, wParam, lParam);
}

// Permission model has no Windows equivalent: the hook just works.
bool hasAccessibilityPermission() { return true; }
bool requestAccessibilityPermission() { return true; }
void openAccessibilitySettings() {}
void startPermissionPolling() {}
bool awaitingPermission() { return false; }

// --- Mouse ------------------------------------------------------------------

void warpCursor(Point position)
{
    auto resolution = primaryDeviceResolution;

    INPUT input;
    input.type = INPUT_MOUSE;
    input.mi.dx = position.x * 65536 / resolution.width;
    input.mi.dy = position.y * 65536 / resolution.height;
    input.mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | draggingFlag;
    SendInput(1, &input, INPUT.sizeof);
}

private bool setButtonFlags(ref INPUT down, ref INPUT up, int button)
{
    switch (button)
    {
        case 1:
            down.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
            up.mi.dwFlags = MOUSEEVENTF_LEFTUP;
            return true;
        case 2:
            down.mi.dwFlags = MOUSEEVENTF_MIDDLEDOWN;
            up.mi.dwFlags = MOUSEEVENTF_MIDDLEUP;
            return true;
        case 3:
            down.mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
            up.mi.dwFlags = MOUSEEVENTF_RIGHTUP;
            return true;
        case 4:
            down.mi.dwFlags = MOUSEEVENTF_WHEEL;
            down.mi.mouseData = WHEEL_DELTA;
            up.mi.dwFlags = 0;
            return true;
        case 5:
            down.mi.dwFlags = MOUSEEVENTF_WHEEL;
            down.mi.mouseData = -WHEEL_DELTA;
            up.mi.dwFlags = 0;
            return true;
        default:
            return false;
    }
}

void mouseClick(int button, long delayMilliseconds)
{
    import core.thread.osthread : Thread;
    import core.time : dur;

    INPUT[2] inputs;
    inputs[0].type = INPUT_MOUSE;
    inputs[1].type = INPUT_MOUSE;

    if (!setButtonFlags(inputs[0], inputs[1], button)) return;

    if (delayMilliseconds == 0)
    {
        SendInput(2, inputs.ptr, INPUT.sizeof);
    }
    else
    {
        SendInput(1, inputs.ptr, INPUT.sizeof);
        Thread.sleep(dur!("msecs")(delayMilliseconds));
        SendInput(1, inputs.ptr + 1, INPUT.sizeof);
    }
}

void mouseDoubleClick(int button, long delayMilliseconds)
{
    import core.thread.osthread : Thread;
    import core.time : dur;

    INPUT[4] inputs;
    inputs[0].type = INPUT_MOUSE;
    inputs[1].type = INPUT_MOUSE;

    if (!setButtonFlags(inputs[0], inputs[1], button)) return;

    inputs[2] = inputs[0];
    inputs[3] = inputs[1];

    if (delayMilliseconds == 0)
    {
        SendInput(4, inputs.ptr, INPUT.sizeof);
    }
    else
    {
        SendInput(1, inputs.ptr, INPUT.sizeof);
        Thread.sleep(dur!("msecs")(delayMilliseconds));
        SendInput(1, inputs.ptr + 1, INPUT.sizeof);

        SendInput(1, inputs.ptr + 2, INPUT.sizeof);
        Thread.sleep(dur!("msecs")(delayMilliseconds));
        SendInput(1, inputs.ptr + 3, INPUT.sizeof);
    }
}

void mouseDragToggle(int button, BitFlags!ModifierKey modifiers)
{
    INPUT mouseInput;
    mouseInput.type = INPUT_MOUSE;

    switch (button)
    {
        case 1:
            mouseInput.mi.dwFlags = !draggingFlag ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
            break;
        case 2:
            mouseInput.mi.dwFlags = !draggingFlag ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
            break;
        case 3:
            mouseInput.mi.dwFlags = !draggingFlag ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
            break;
        default:
            showError("Invalid mouse button");
            return;
    }

    if (draggingFlag && modifiers)
    {
        INPUT[] keyDownInputs;
        INPUT[] keyUpInputs;

        void addModifier(ushort vk)
        {
            INPUT keyboardInput;
            keyboardInput.type = INPUT_KEYBOARD;
            keyboardInput.ki.wVk = vk;
            keyDownInputs ~= keyboardInput;

            keyboardInput.ki.dwFlags = KEYEVENTF_KEYUP;
            keyUpInputs ~= keyboardInput;
        }

        if (modifiers & ModifierKey.ctrl)   addModifier(VK_CONTROL);
        if (modifiers & ModifierKey.shift)  addModifier(VK_SHIFT);
        if (modifiers & ModifierKey.alt)    addModifier(VK_MENU);
        if (modifiers & ModifierKey.super_) addModifier(VK_LWIN);

        INPUT[] inputs = keyDownInputs ~ [mouseInput] ~ keyUpInputs;
        SendInput(cast(DWORD) inputs.length, inputs.ptr, INPUT.sizeof);
    }
    else
    {
        SendInput(1, &mouseInput, INPUT.sizeof);
    }

    draggingFlag = !draggingFlag ? mouseInput.mi.dwFlags : 0;
}

bool isDragging()
{
    return draggingFlag != 0;
}

// --- Focused window ---------------------------------------------------------

Nullable!Rect focusedWindowRect()
{
    Rect rect;

    if (!GetWindowRect(GetForegroundWindow(), &rect))
    {
        return Nullable!Rect.init;
    }

    return Nullable!Rect(rect);
}
