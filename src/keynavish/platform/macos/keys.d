module keynavish.platform.macos.keys;

version (OSX):

import std.typecons : Nullable;
import keynavish.types;
import keynavish.platform.macos.coregraphics;

//
// Key-name resolution.
//
// macOS virtual keycodes are positional -- they never change with the keyboard
// layout. X11 keysyms and Windows virtual-key codes both do follow the layout,
// so a fixed kVK_* table would make the same config file behave differently
// here from keynav and the Windows build on any non-QWERTY layout. Character
// keys are therefore resolved through the active layout with UCKeyTranslate.
//

// --- Carbon / HIToolbox bindings -------------------------------------------

private extern (C) nothrow
{
    alias TISInputSourceRef = void*;
    alias CFDataRef = void*;
    alias OSStatus = int;
    alias UniChar = ushort;
    // MacTypes.h has `typedef unsigned long UniCharCount`, which is 64-bit on
    // LP64 macOS, not UInt32.
    alias UniCharCount = ulong;

    TISInputSourceRef TISCopyCurrentKeyboardLayoutInputSource();
    TISInputSourceRef TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    void* TISGetInputSourceProperty(TISInputSourceRef inputSource, CFStringRef propertyKey);

    extern __gshared CFStringRef kTISPropertyUnicodeKeyLayoutData;

    const(ubyte)* CFDataGetBytePtr(CFDataRef data);
    long CFDataGetLength(CFDataRef data);

    uint LMGetKbdType();

    OSStatus UCKeyTranslate(const(void)* keyLayoutPtr,
                            ushort virtualKeyCode,
                            ushort keyAction,
                            uint modifierKeyState,
                            uint keyboardType,
                            uint keyTranslateOptions,
                            uint* deadKeyState,
                            UniCharCount maxStringLength,
                            UniCharCount* actualStringLength,
                            UniChar* unicodeString);
}

private enum kUCKeyActionDisplay = 3;
private enum kUCKeyTranslateNoDeadKeysMask = 1;

// --- Positional keycodes for non-character keys -----------------------------

enum : KeyCode
{
    kVK_Return        = 0x24,
    kVK_Tab           = 0x30,
    kVK_Space         = 0x31,
    kVK_Backspace     = 0x33,
    kVK_Escape        = 0x35,
    kVK_Command       = 0x37,
    kVK_RightCommand  = 0x36,
    kVK_Shift         = 0x38,
    kVK_Option        = 0x3A,
    kVK_Control       = 0x3B,
    kVK_RightShift    = 0x3C,
    kVK_RightOption   = 0x3D,
    kVK_RightControl  = 0x3E,
    kVK_Help          = 0x72,
    kVK_Home          = 0x73,
    kVK_PageUp        = 0x74,
    kVK_ForwardDelete = 0x75,
    kVK_End           = 0x77,
    kVK_PageDown      = 0x79,
    kVK_LeftArrow     = 0x7B,
    kVK_RightArrow    = 0x7C,
    kVK_DownArrow     = 0x7D,
    kVK_UpArrow       = 0x7E,
}

// Keypad codes are not contiguous.
private immutable KeyCode[10] keypadCodes =
    [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C];

// --- Layout-derived character map -------------------------------------------

private KeyCode[dchar] charToKeyCode;
private dchar[KeyCode] keyCodeToChar;
private bool layoutMapBuilt;

/// Translates one keycode through a layout. `shifted` picks the shifted
/// character (e.g. '@' rather than '2' on a US layout).
private dchar translateKeyCode(const(ubyte)* layout, KeyCode keyCode, bool shifted)
{
    // UCKeyTranslate takes the Carbon modifier field shifted right by 8;
    // shiftKey is 1 << 9, so the shift state is 1 << 1.
    uint modifierState = shifted ? 2 : 0;

    uint deadKeyState;
    UniChar[8] buffer;
    UniCharCount length;

    auto status = UCKeyTranslate(layout,
                                 cast(ushort) keyCode,
                                 kUCKeyActionDisplay,
                                 modifierState,
                                 LMGetKbdType(),
                                 kUCKeyTranslateNoDeadKeysMask,
                                 &deadKeyState,
                                 buffer.length,
                                 &length,
                                 buffer.ptr);

    if (status != 0 || length == 0) return dchar.init;

    return cast(dchar) buffer[0];
}

/// Rebuilds the character map from the active keyboard layout. Called at
/// startup and whenever the selected input source changes.
void buildLayoutMap()
{
    charToKeyCode = null;
    keyCodeToChar = null;

    // Fetched once rather than per keycode: this runs 256 translations.
    auto layout = currentKeyboardLayoutData();
    if (layout is null) return;

    layoutMapBuilt = true;

    // 0x00..0x7F covers every key the layout can produce a character for.
    foreach (KeyCode keyCode; 0 .. 0x80)
    {
        auto unshifted = translateKeyCode(layout.ptr, keyCode, false);
        auto shifted = translateKeyCode(layout.ptr, keyCode, true);

        if (unshifted != dchar.init)
        {
            // First keycode wins, so the main row beats the keypad for digits.
            if (unshifted !in charToKeyCode) charToKeyCode[unshifted] = keyCode;
            if (keyCode !in keyCodeToChar) keyCodeToChar[keyCode] = unshifted;
        }

        if (shifted != dchar.init && shifted !in charToKeyCode)
        {
            charToKeyCode[shifted] = keyCode;
        }
    }
}

/// A copy of the active Unicode key layout, falling back to the ASCII-capable
/// layout when the selected input source has none (input methods such as
/// Japanese, Chinese and Korean report no layout data -- without the fallback
/// every character binding would fail to resolve).
///
/// The bytes are copied rather than referenced: TISGetInputSourceProperty
/// follows the Core Foundation "get rule", so the CFData is owned by the input
/// source and keeping a pointer into it past the CFRelease below would be a
/// use-after-free.
private ubyte[] currentKeyboardLayoutData()
{
    static ubyte[] layoutDataFrom(TISInputSourceRef source)
    {
        if (source is null) return null;
        scope (exit) CFRelease(source);

        auto layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
        if (layoutData is null) return null;

        auto bytes = CFDataGetBytePtr(layoutData);
        auto length = CFDataGetLength(layoutData);

        if (bytes is null || length <= 0) return null;

        return bytes[0 .. cast(size_t) length].dup;
    }

    auto layout = layoutDataFrom(TISCopyCurrentKeyboardLayoutInputSource());
    if (layout !is null) return layout;

    return layoutDataFrom(TISCopyCurrentASCIICapableKeyboardLayoutInputSource());
}

/// Handles a keyboard layout change: rebuild the character map, then re-resolve
/// every binding against it.
///
/// Rebuilding the map alone would not be enough: bindings store resolved
/// keycodes, so they would keep pointing at the previous layout's physical keys.
void rebuildForLayoutChange()
{
    import keynavish.commands : reloadAllKeyBindings;

    buildLayoutMap();

    reloadAllKeyBindings();
}

/// The character the given keycode produces unshifted on the active layout, or
/// dchar.init. Used by grid-nav, which matches cells by letter.
dchar characterForKeyCode(KeyCode keyCode)
{
    if (!layoutMapBuilt) buildLayoutMap();

    auto found = keyCode in keyCodeToChar;
    return found is null ? dchar.init : *found;
}

// --- Key name resolution ----------------------------------------------------

/// Character that a keynav key name stands for, or dchar.init if the name is
/// not a character key.
private dchar characterForKeyName(string name)
{
    // Lowercase only, matching the Windows table: an uppercase name would
    // resolve through the shifted half of the map and bind the unshifted key.
    if (name.length == 1 && ((name[0] >= 'a' && name[0] <= 'z')
                             || (name[0] >= '0' && name[0] <= '9')))
    {
        return name[0];
    }

    switch (name)
    {
        case "semicolon":    return ';';
        case "bracketleft":  return '[';
        case "bracketright": return ']';
        case "backslash":    return '\\';
        case "at":           return '@';
        case "plus":         return '+';
        case "comma":        return ',';
        case "minus":        return '-';
        case "period":       return '.';
        case "slash":        return '/';
        case "apostrophe":   return '\'';
        case "grave":        return '`';
        case "equal":        return '=';
        default:             return dchar.init;
    }
}

/// Resolves a keynav key name to a macOS virtual keycode.
Nullable!KeyCode resolveKeyName(string name)
{
    if (!layoutMapBuilt) buildLayoutMap();

    alias Result = Nullable!KeyCode;

    switch (name)
    {
        case "Super_L":   return Result(kVK_Command);
        case "Super_R":   return Result(kVK_RightCommand);
        case "Escape":    return Result(kVK_Escape);
        case "Tab":       return Result(kVK_Tab);
        case "Left":      return Result(kVK_LeftArrow);
        case "Up":        return Result(kVK_UpArrow);
        case "Right":     return Result(kVK_RightArrow);
        case "Down":      return Result(kVK_DownArrow);
        case "Home":      return Result(kVK_Home);
        case "End":       return Result(kVK_End);
        case "Prior":
        case "Page_Up":   return Result(kVK_PageUp);
        case "Next":
        case "Page_Down": return Result(kVK_PageDown);
        case "Delete":    return Result(kVK_ForwardDelete);
        case "BackSpace": return Result(kVK_Backspace);
        case "Return":    return Result(kVK_Return);
        case "space":     return Result(kVK_Space);

        // macOS has no Insert key. Help occupies the same physical position on
        // an extended keyboard, which is the closest thing available.
        case "Insert":    return Result(kVK_Help);

        default: break;
    }

    // Keypad keys, e.g. KP_7.
    if (name.length == 4 && name[0 .. 3] == "KP_" && name[3] >= '0' && name[3] <= '9')
    {
        return Result(keypadCodes[name[3] - '0']);
    }

    auto character = characterForKeyName(name);
    if (character != dchar.init)
    {
        auto found = character in charToKeyCode;
        if (found !is null)
        {
            return Result(*found);
        }

        // The name is a known character key, but the active layout has no key
        // that produces it. Caller reports this as an unresolvable key.
        return Result.init;
    }

    return Result.init;
}

/// Escape, which cancels grid-nav selection.
bool isEscapeKey(KeyCode keyCode)
{
    return keyCode == kVK_Escape;
}

/// Modifier keys must never be swallowed, or the OS loses track of their state
/// while the grid is up.
bool isModifierKey(KeyCode keyCode)
{
    switch (keyCode)
    {
        case kVK_Command:
        case kVK_RightCommand:
        case kVK_Shift:
        case kVK_RightShift:
        case kVK_Option:
        case kVK_RightOption:
        case kVK_Control:
        case kVK_RightControl:
        case 0x39: // Caps Lock
        case 0x3F: // Fn
            return true;
        default:
            return false;
    }
}
