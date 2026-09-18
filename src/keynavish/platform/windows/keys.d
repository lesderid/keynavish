module keynavish.platform.windows.keys;

version (Windows):

import std.typecons : Nullable;
import core.sys.windows.windows;
import keynavish.types;

//
// Key-name resolution.
//
// Windows virtual-key codes already follow the active keyboard layout -- the
// layout driver maps scancode to VK -- so no explicit translation step is
// needed here, unlike on macOS.
//

/// Resolves a keynav key name to a Windows virtual-key code.
Nullable!KeyCode resolveKeyName(string name)
{
    alias Result = Nullable!KeyCode;

    switch (name)
    {
        case "Super_L":     return Result(cast(KeyCode) VK_LWIN);
        case "Super_R":     return Result(cast(KeyCode) VK_RWIN);
        case "semicolon":   return Result(cast(KeyCode) VK_OEM_1);
        case "Escape":      return Result(cast(KeyCode) VK_ESCAPE);
        case "Tab":         return Result(cast(KeyCode) VK_TAB);
        case "Left":        return Result(cast(KeyCode) VK_LEFT);
        case "Up":          return Result(cast(KeyCode) VK_UP);
        case "Right":       return Result(cast(KeyCode) VK_RIGHT);
        case "Down":        return Result(cast(KeyCode) VK_DOWN);
        case "Insert":      return Result(cast(KeyCode) VK_INSERT);
        case "Home":        return Result(cast(KeyCode) VK_HOME);
        case "End":         return Result(cast(KeyCode) VK_END);
        case "Prior":
        case "Page_Up":     return Result(cast(KeyCode) VK_PRIOR);
        case "Next":
        case "Page_Down":   return Result(cast(KeyCode) VK_NEXT);
        case "Delete":      return Result(cast(KeyCode) VK_DELETE);
        case "BackSpace":   return Result(cast(KeyCode) VK_BACK);
        case "Return":      return Result(cast(KeyCode) VK_RETURN);
        case "space":       return Result(cast(KeyCode) VK_SPACE);
        case "bracketleft": return Result(cast(KeyCode) VK_OEM_4);
        case "backslash":   return Result(cast(KeyCode) VK_OEM_5);
        case "bracketright":return Result(cast(KeyCode) VK_OEM_6);

        //HACK: This doesn't have its own vkcode on Windows, but on X11 it has its own keysym
        case "at":          return Result(cast(KeyCode) '2');

        case "plus":
        case "equal":       return Result(cast(KeyCode) VK_OEM_PLUS);
        case "comma":       return Result(cast(KeyCode) VK_OEM_COMMA);
        case "minus":       return Result(cast(KeyCode) VK_OEM_MINUS);
        case "period":      return Result(cast(KeyCode) VK_OEM_PERIOD);
        case "slash":       return Result(cast(KeyCode) VK_OEM_2);
        case "grave":       return Result(cast(KeyCode) VK_OEM_3);
        case "apostrophe":  return Result(cast(KeyCode) VK_OEM_7);

        default: break;
    }

    if (name.length == 1 && name[0] >= 'a' && name[0] <= 'z')
    {
        return Result(cast(KeyCode)('A' + (name[0] - 'a')));
    }

    if (name.length == 1 && name[0] >= '0' && name[0] <= '9')
    {
        return Result(cast(KeyCode) name[0]);
    }

    if (name.length == 4 && name[0 .. 3] == "KP_" && name[3] >= '0' && name[3] <= '9')
    {
        return Result(cast(KeyCode)(0x60 + name[3] - '0'));
    }

    return Result.init;
}

/// The character a keycode corresponds to, used by grid-nav's letter matching.
/// Windows virtual-key codes for letters are the ASCII uppercase values.
dchar characterForKeyCode(KeyCode keyCode)
{
    import std.ascii : toLower;

    if (keyCode >= 'A' && keyCode <= 'Z')
    {
        return toLower(cast(char) keyCode);
    }

    return dchar.init;
}

void buildLayoutMap()
{
    // Nothing to do: Windows resolves layout at the driver level.
}

/// Escape, which cancels grid-nav selection.
bool isEscapeKey(KeyCode keyCode)
{
    return keyCode == VK_ESCAPE;
}

/// Modifier keys must never be swallowed, or the OS loses track of their state
/// while the grid is up.
bool isModifierKey(KeyCode keyCode)
{
    return (keyCode >= VK_LSHIFT && keyCode <= VK_RCONTROL)
        || keyCode == VK_LWIN
        || keyCode == VK_RWIN;
}
