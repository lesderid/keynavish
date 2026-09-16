module keynavish.platform.macos.input;

version (OSX):

import std.typecons : BitFlags, Nullable;
import keynavish;
import keynavish.types;
import keynavish.platform.macos.coregraphics;
import keynavish.platform.macos.shim;
import keynavish.platform.macos.display;
import keynavish.platform.macos.keys;

//
// Global keyboard capture via CGEventTap, and mouse synthesis via CGEvent.
// Replaces the Windows low-level keyboard hook and SendInput. See §6.2 and §6.6.
//

private CFMachPortRef eventTap;
private bool permissionPollActive;

// Carbon: reports whether some application has secure keyboard entry enabled.
private extern (C) nothrow @nogc bool IsSecureEventInputEnabled();

/// True when another application has secure input enabled, which stops macOS
/// delivering key events to ANY event tap, keynavish included.
///
/// This is not a permission problem and not something keynavish can work around
/// -- it is the mechanism that stops password fields being keylogged, and it
/// applies system-wide for as long as the other app holds it. The most common
/// cause by far is Terminal's "Secure Keyboard Entry" setting, which holds it
/// for as long as Terminal is running, not only while Terminal is focused.
///
/// Worth surfacing because the symptom is otherwise indistinguishable from
/// keynavish being broken: the hotkey simply does nothing, silently.
bool keyboardInputBlocked()
{
    return IsSecureEventInputEnabled();
}

// --- Accessibility permission ----------------------------------------------

bool hasAccessibilityPermission()
{
    return AXIsProcessTrusted();
}

/// Shows the system's own "would like to control this computer" prompt, and
/// reports whether the process is already trusted.
///
/// This is what makes first run match what the README promises: creating an
/// event tap while untrusted fails silently, so without an explicit prompt the
/// user would only ever see a dimmed menu bar icon.
bool requestAccessibilityPermission()
{
    return knv_request_accessibility_permission() != 0;
}

void openAccessibilitySettings()
{
    knv_open_url("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
}

// --- Event tap --------------------------------------------------------------

private BitFlags!ModifierKey modifiersFromFlags(CGEventFlags flags)
{
    BitFlags!ModifierKey modifiers = ModifierKey.none;

    if (flags & kCGEventFlagMaskControl)   modifiers |= ModifierKey.ctrl;
    if (flags & kCGEventFlagMaskShift)     modifiers |= ModifierKey.shift;
    if (flags & kCGEventFlagMaskAlternate) modifiers |= ModifierKey.alt;
    // keynav's `super` is the Windows key on X11; Command is its macOS analogue.
    if (flags & kCGEventFlagMaskCommand)   modifiers |= ModifierKey.super_;

    return modifiers;
}

private extern (C) CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type,
                                          CGEventRef event, void* userInfo) nothrow
{
    // The system disables a tap whose callback is too slow, and silently stops
    // delivering events until it is re-enabled. This is not an edge case; it
    // happens under load. See MACOS-PORT.md §6.2.
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput)
    {
        try
        {
            debugLog("event tap disabled by %s; re-enabling",
                     type == kCGEventTapDisabledByTimeout ? "timeout" : "user input");
        }
        catch (Throwable)
        {
        }

        if (eventTap !is null)
        {
            CGEventTapEnable(eventTap, true);

            // Re-enabling fails when the tap is dead rather than merely
            // throttled -- most often because Accessibility permission was
            // revoked while running. Without this the app would sit there
            // looking healthy while silently receiving nothing ever again.
            //
            // The teardown is deferred rather than done here: this callback is
            // running on the tap's own port, which it must not destroy.
            if (!CGEventTapIsEnabled(eventTap))
            {
                knv_dispatch_async(&recoverLostTap);
            }
        }
        return event;
    }

    if (type != kCGEventKeyDown)
    {
        return event;
    }

    try
    {
        auto keyCode = cast(KeyCode) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        auto modifiers = modifiersFromFlags(CGEventGetFlags(event));

        if (handleKeyDown(keyCode, modifiers))
        {
            // Returning null consumes the event, the equivalent of returning 1
            // from the Windows hook.
            return null;
        }
    }
    catch (Throwable)
    {
        // Never let an exception escape into CoreGraphics; pass the key through.
    }

    return event;
}

/// Tears down a tap that can no longer be re-enabled and returns to waiting for
/// permission, so the app recovers by itself once it is granted again.
private extern (C) void recoverLostTap() nothrow
{
    try
    {
        debugLog("event tap could not be re-enabled; returning to permission polling");

        uninstallKeyboardHook();
        startPermissionPolling();
        rebuildStatusMenu();
    }
    catch (Throwable)
    {
    }
}

private void uninstallKeyboardHook()
{
    if (eventTap is null) return;

    CGEventTapEnable(eventTap, false);
    CFRelease(eventTap);
    eventTap = null;
}

/// Installs the event tap. Returns false when Accessibility permission has not
/// been granted, in which case the caller should keep running and retry.
bool installKeyboardHook()
{
    // A non-null handle is not the same as a working tap: a disabled one must be
    // discarded and rebuilt, or this would report success for a tap that
    // delivers nothing.
    if (eventTap !is null)
    {
        if (CGEventTapIsEnabled(eventTap))
        {
            return true;
        }

        uninstallKeyboardHook();
    }

    auto mask = CGEventMaskBit(kCGEventKeyDown);

    eventTap = CGEventTapCreate(kCGSessionEventTap,
                                kCGHeadInsertEventTap,
                                kCGEventTapOptionDefault,
                                mask,
                                &tapCallback,
                                null);

    if (eventTap is null)
    {
        return false;
    }

    auto source = CFMachPortCreateRunLoopSource(null, eventTap, 0);
    if (source is null)
    {
        CFRelease(eventTap);
        eventTap = null;
        return false;
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);

    CGEventTapEnable(eventTap, true);

    buildLayoutMap();

    knv_set_layout_changed_callback(&layoutChangedCallback);

    return true;
}

private extern (C) void layoutChangedCallback() nothrow
{
    try
    {
        debugLog("keyboard layout changed; re-resolving key bindings");

        rebuildForLayoutChange();
    }
    catch (Throwable)
    {
    }
}

private extern (C) void permissionPollCallback() nothrow
{
    try
    {
        if (!hasAccessibilityPermission())
        {
            return;
        }

        if (installKeyboardHook())
        {
            knv_cancel_timer();
            permissionPollActive = false;
            setStatusItemAttention(false);
            rebuildStatusMenu();
        }
    }
    catch (Throwable)
    {
    }
}

/// Starts polling for the Accessibility grant, so the app becomes functional
/// the moment the user grants it without needing a restart (§7.1).
void startPermissionPolling()
{
    if (permissionPollActive) return;

    permissionPollActive = true;
    setStatusItemAttention(true);

    knv_schedule_timer(1.0, &permissionPollCallback);
}

bool awaitingPermission()
{
    return permissionPollActive;
}

// --- Mouse ------------------------------------------------------------------

private Nullable!int draggingButton;

private CGMouseButton cgButton(int button)
{
    switch (button)
    {
        case 2:  return kCGMouseButtonCenter;
        case 3:  return kCGMouseButtonRight;
        default: return kCGMouseButtonLeft;
    }
}

private CGEventType downEventType(int button)
{
    switch (button)
    {
        case 2:  return kCGEventOtherMouseDown;
        case 3:  return kCGEventRightMouseDown;
        default: return kCGEventLeftMouseDown;
    }
}

private CGEventType upEventType(int button)
{
    switch (button)
    {
        case 2:  return kCGEventOtherMouseUp;
        case 3:  return kCGEventRightMouseUp;
        default: return kCGEventLeftMouseUp;
    }
}

private CGEventType draggedEventType(int button)
{
    switch (button)
    {
        case 2:  return kCGEventOtherMouseDragged;
        case 3:  return kCGEventRightMouseDragged;
        default: return kCGEventLeftMouseDragged;
    }
}

private void postMouseEvent(CGEventType type, Point position, int button, int clickState = 0)
{
    auto event = CGEventCreateMouseEvent(null, type,
                                         CGPoint(position.x, position.y),
                                         cgButton(button));
    if (event is null) return;
    scope (exit) CFRelease(event);

    if (clickState > 0)
    {
        // macOS apps read clickState to recognise a double click; two plain
        // click pairs are seen as two separate clicks. See §6.6.
        CGEventSetIntegerValueField(event, kCGMouseEventClickState, clickState);
    }

    CGEventPost(kCGHIDEventTap, event);
}

void warpCursor(Point position)
{
    // While a button is held the motion must be posted as a drag, or the target
    // application never sees the drag gesture.
    auto type = draggingButton.isNull
        ? kCGEventMouseMoved
        : draggedEventType(draggingButton.get());

    postMouseEvent(type, position, draggingButton.isNull ? 1 : draggingButton.get());
}

void mouseClick(int button, long delayMilliseconds)
{
    import core.thread.osthread : Thread;
    import core.time : dur;

    if (button == 4 || button == 5)
    {
        scrollWheel(button == 4 ? 1 : -1);
        return;
    }

    auto position = cursorPosition;

    postMouseEvent(downEventType(button), position, button, 1);

    if (delayMilliseconds > 0)
    {
        Thread.sleep(dur!"msecs"(delayMilliseconds));
    }

    postMouseEvent(upEventType(button), position, button, 1);
}

void mouseDoubleClick(int button, long delayMilliseconds)
{
    import core.thread.osthread : Thread;
    import core.time : dur;

    auto position = cursorPosition;

    foreach (clickState; 1 .. 3)
    {
        postMouseEvent(downEventType(button), position, button, clickState);

        if (delayMilliseconds > 0)
        {
            Thread.sleep(dur!"msecs"(delayMilliseconds));
        }

        postMouseEvent(upEventType(button), position, button, clickState);
    }
}

void scrollWheel(int lines)
{
    auto event = CGEventCreateScrollWheelEvent(null, kCGScrollEventUnitLine, 1, lines);
    if (event is null) return;
    scope (exit) CFRelease(event);

    CGEventPost(kCGHIDEventTap, event);
}

/// Toggles a drag on or off, matching the Windows `drag` command's behaviour.
void mouseDragToggle(int button, BitFlags!ModifierKey modifiers)
{
    auto position = cursorPosition;

    if (draggingButton.isNull)
    {
        postMouseEvent(downEventType(button), position, button, 1);
        draggingButton = button;
    }
    else
    {
        auto held = draggingButton.get();

        // Modifiers are applied to the mouse event itself rather than
        // synthesised as separate key presses, which is both simpler and less
        // racy than the Windows approach. See §6.6.
        auto event = CGEventCreateMouseEvent(null, upEventType(held),
                                             CGPoint(position.x, position.y),
                                             cgButton(held));
        if (event !is null)
        {
            scope (exit) CFRelease(event);

            CGEventFlags flags = 0;
            if (modifiers & ModifierKey.ctrl)   flags |= kCGEventFlagMaskControl;
            if (modifiers & ModifierKey.shift)  flags |= kCGEventFlagMaskShift;
            if (modifiers & ModifierKey.alt)    flags |= kCGEventFlagMaskAlternate;
            if (modifiers & ModifierKey.super_) flags |= kCGEventFlagMaskCommand;

            if (flags) CGEventSetFlags(event, flags);

            CGEventPost(kCGHIDEventTap, event);
        }

        draggingButton.nullify();
    }
}

bool isDragging()
{
    return !draggingButton.isNull;
}

// --- Focused window ---------------------------------------------------------

private CFStringRef cfString(string s)
{
    import std.string : toStringz;

    return CFStringCreateWithCString(null, s.toStringz, kCFStringEncodingUTF8);
}

/// Bounds of the focused window, for `windowzoom`. Uses the Accessibility API,
/// which reports the actually-focused window rather than guessing from the
/// on-screen window list. Needs no permission beyond the one the tap already
/// requires. See §6.7.
Nullable!Rect focusedWindowRect()
{
    import std.math : round;

    alias Result = Nullable!Rect;

    auto systemWide = AXUIElementCreateSystemWide();
    if (systemWide is null) return Result.init;
    scope (exit) CFRelease(systemWide);

    auto focusedAppAttr = cfString("AXFocusedApplication");
    scope (exit) if (focusedAppAttr !is null) CFRelease(focusedAppAttr);

    CFTypeRef app;
    if (AXUIElementCopyAttributeValue(systemWide, focusedAppAttr, &app) != kAXErrorSuccess
        || app is null)
    {
        return Result.init;
    }
    scope (exit) CFRelease(app);

    auto focusedWindowAttr = cfString("AXFocusedWindow");
    scope (exit) if (focusedWindowAttr !is null) CFRelease(focusedWindowAttr);

    CFTypeRef window;
    if (AXUIElementCopyAttributeValue(app, focusedWindowAttr, &window) != kAXErrorSuccess
        || window is null)
    {
        return Result.init;
    }
    scope (exit) CFRelease(window);

    auto positionAttr = cfString("AXPosition");
    auto sizeAttr = cfString("AXSize");
    scope (exit)
    {
        if (positionAttr !is null) CFRelease(positionAttr);
        if (sizeAttr !is null) CFRelease(sizeAttr);
    }

    CFTypeRef positionValue;
    CFTypeRef sizeValue;

    if (AXUIElementCopyAttributeValue(window, positionAttr, &positionValue) != kAXErrorSuccess
        || positionValue is null)
    {
        return Result.init;
    }
    scope (exit) CFRelease(positionValue);

    if (AXUIElementCopyAttributeValue(window, sizeAttr, &sizeValue) != kAXErrorSuccess
        || sizeValue is null)
    {
        return Result.init;
    }
    scope (exit) CFRelease(sizeValue);

    CGPoint position;
    CGSize size;

    if (!AXValueGetValue(positionValue, kAXValueTypeCGPoint, &position)
        || !AXValueGetValue(sizeValue, kAXValueTypeCGSize, &size))
    {
        return Result.init;
    }

    return Result(Rect(cast(int) round(position.x),
                       cast(int) round(position.y),
                       cast(int) round(position.x + size.width),
                       cast(int) round(position.y + size.height)));
}
