module keynavish.platform.macos.input;

version (OSX):

import core.time : Duration, MonoTime;
import std.typecons : BitFlags, Nullable;
import keynavish;
import keynavish.types;
import keynavish.platform.macos.coregraphics;
import keynavish.platform.macos.shim;
import keynavish.platform.macos.display;
import keynavish.platform.macos.keys;

//
// Global keyboard capture via CGEventTap, and mouse synthesis via CGEvent.
//

private CFMachPortRef eventTap;

/// Kept so the source can be removed from the run loop on teardown. Releasing
/// only the tap leaves the run loop holding a source for a dead port.
private CFRunLoopSourceRef eventTapSource;
private bool permissionPollActive;

// Carbon: reports whether some application has secure keyboard entry enabled.
// While it is, macOS delivers key events to no event tap at all, keynavish
// included, and there is nothing keynavish can do about it but say so.
private extern (C) nothrow @nogc bool IsSecureEventInputEnabled();

/// Describes what is blocking keyboard input and, where possible, how to turn
/// it off. Empty when nothing is blocking.
struct SecureInputBlocker
{
    bool active;
    int pid;
    string appName;      /// Empty when the process could not be identified.
    string instruction;  /// Empty when there is no app-specific advice.
}

SecureInputBlocker secureInputBlocker()
{
    import core.stdc.string : strlen;

    SecureInputBlocker blocker;

    if (!IsSecureEventInputEnabled()) return blocker;

    blocker.active = true;
    blocker.pid = knv_secure_input_pid();

    static string fromC(const(char)* value)
    {
        return value is null ? null : value[0 .. strlen(value)].idup;
    }

    // Everything is resolved from the single pid read above: re-querying could
    // name one app while the pid the menu later acts on belongs to another.
    blocker.appName = fromC(knv_app_name_for_pid(blocker.pid));

    blocker.instruction = secureInputInstruction(fromC(knv_bundle_id_for_pid(blocker.pid)),
                                                 blocker.appName);

    return blocker;
}

/// How to turn off secure keyboard entry in the application holding it.
///
/// Split out from the lookup above so it can be tested without a process
/// actually having to hold secure input.
string secureInputInstruction(string bundleId, string appName)
{
    switch (bundleId)
    {
        case "com.apple.Terminal":
            return "Turn off Terminal ▸ Secure Keyboard Entry";
        case "com.googlecode.iterm2":
            return "Turn off iTerm2 ▸ Secure Keyboard Entry";
        default:
            break;
    }

    if (appName.length > 0)
    {
        return "Turn off secure keyboard entry in " ~ appName;
    }

    return null;
}

/// Brings the blocking application to the front so its menu is reachable.
void activateSecureInputBlocker(int pid)
{
    if (pid != 0) knv_activate_app_with_pid(pid);
}

// --- Accessibility permission ----------------------------------------------

bool hasAccessibilityPermission()
{
    return AXIsProcessTrusted();
}

/// Shows the system's own "would like to control this computer" prompt, and
/// reports whether the process is already trusted.
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
    // delivering events until it is re-enabled. This happens under load.
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput)
    {
        if (eventTap !is null)
        {
            CGEventTapEnable(eventTap, true);

            // Re-enabling fails when the tap is dead rather than merely
            // throttled, most often because Accessibility permission was
            // revoked while running. The teardown is deferred because this
            // callback runs on the tap's own port, which it must not destroy.
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
    catch (Throwable t)
    {
        // Never let an exception escape into CoreGraphics -- but don't swallow
        // it either. What throws here is a user command failing, such as a
        // shell command that cannot spawn or a config that cannot be read, and
        // without this the binding would silently do nothing. Windows reports
        // these too, through the exception wrapper on its hook. showError
        // defers onto the main queue, so it is safe to call from the tap.
        try
        {
            import std.exception : assumeWontThrow;

            showError("Command failed: " ~ t.message.assumeWontThrow.idup);
        }
        catch (Throwable)
        {
        }
    }

    return event;
}

/// Tears down a tap that can no longer be re-enabled and returns to waiting for
/// permission, so the app recovers by itself once it is granted again.
private extern (C) void recoverLostTap() nothrow
{
    try
    {
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

    if (eventTapSource !is null)
    {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, kCFRunLoopCommonModes);
        CFRelease(eventTapSource);
        eventTapSource = null;
    }

    // Invalidated before release so the port is actually torn down rather than
    // lingering until the last internal reference happens to go.
    CFMachPortInvalidate(eventTap);
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

    eventTapSource = CFMachPortCreateRunLoopSource(null, eventTap, 0);
    if (eventTapSource is null)
    {
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = null;
        return false;
    }

    // The reference is retained rather than released here, so uninstall can
    // remove this exact source from the run loop again.
    CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, kCFRunLoopCommonModes);

    CGEventTapEnable(eventTap, true);

    buildLayoutMap();

    knv_set_layout_changed_callback(&layoutChangedCallback);

    return true;
}

private extern (C) void layoutChangedCallback() nothrow
{
    try
    {
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

            // The layout-change callback is only registered once the hook
            // installs, so a layout switched while the user was in System
            // Settings granting permission went unnoticed: the map is current
            // again by now, but the bindings still hold the startup layout's
            // keycodes.
            reloadAllKeyBindings();

            setStatusItemAttention(false);
            rebuildStatusMenu();
        }
    }
    catch (Throwable)
    {
    }
}

/// Starts polling for the Accessibility grant, so the app becomes functional
/// the moment the user grants it without needing a restart.
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

/// Where the last warp in this command sequence sent the cursor.
///
/// A click following a warp must land where the warp aimed: posting a
/// mouse-moved event and then reading back the cursor position races the move,
/// so the read can still return the pre-warp location. Held for the whole
/// sequence (`warp,click 1,click 1` is a common shape) and cleared at the start
/// of the next one, so it never applies to an unrelated later click.
private Nullable!Point pendingWarpPosition;

/// Clears any warp recorded by a previous command sequence. Called before each
/// sequence runs.
void resetPendingWarp()
{
    pendingWarpPosition.nullify();
}

/// Position a click should be posted at: the pending warp target if this
/// sequence performed one, otherwise wherever the cursor actually is.
private Point clickPosition()
{
    if (!pendingWarpPosition.isNull)
    {
        return pendingWarpPosition.get();
    }

    return cursorPosition;
}

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

//
// Click counting.
//
// A real mouse gets this for free: the window server counts clicks and fills in
// kCGMouseEventClickState, which is what an application reads to tell a double
// click from two single clicks. It does not do that for synthesised events --
// they carry whatever the sender puts in the field -- so `click 1` twice in
// quick succession looked like two unrelated single clicks no matter how fast
// the two commands ran, and text never selected the way it does with a physical
// double click. Windows needs none of this: it derives the double click from
// the event stream itself.
//

/// How far the cursor may move between two clicks and still continue the count.
/// Small enough that two different grid cells never count as a double click,
/// large enough to absorb the rounding between a warp target and the position
/// the window server reports back.
private enum clickSlop = 3;

struct ClickCount
{
    int state;
    int button;
    Point position;
    MonoTime time;
}

private ClickCount lastClick;

/// The clickState for a click of `button` at `position`, continuing the run in
/// `last` when it lands soon enough and close enough, and starting a new one at
/// 1 otherwise. Updates `last` for the click that follows.
///
/// `now` and `interval` are parameters rather than read here so this can be
/// tested without waiting out a real double-click interval.
int advanceClickCount(ref ClickCount last, int button, Point position,
                      MonoTime now, Duration interval)
{
    import std.math : abs;

    auto continues = last.state > 0
        && button == last.button
        && now - last.time <= interval
        && abs(position.x - last.position.x) <= clickSlop
        && abs(position.y - last.position.y) <= clickSlop;

    last.state = continues ? last.state + 1 : 1;
    last.button = button;
    last.position = position;
    last.time = now;

    return last.state;
}

/// The double-click interval the user has set, falling back to the macOS
/// default if the system reports something unusable.
private Duration doubleClickInterval()
{
    import core.time : dur;

    auto seconds = knv_double_click_interval();

    if (!(seconds > 0)) return dur!"msecs"(500);

    return dur!"usecs"(cast(long)(seconds * 1_000_000));
}

private int nextClickState(int button, Point position)
{
    return advanceClickCount(lastClick, button, position,
                             MonoTime.currTime, doubleClickInterval());
}

/// Records a click run the caller counted itself, so whatever comes next
/// continues from it.
private void recordClickCount(int button, Point position, int state)
{
    lastClick = ClickCount(state, button, position, MonoTime.currTime);
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
        // click pairs are seen as two separate clicks.
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

    pendingWarpPosition = position;
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

    auto position = clickPosition();
    auto clickState = nextClickState(button, position);

    postMouseEvent(downEventType(button), position, button, clickState);

    if (delayMilliseconds > 0)
    {
        Thread.sleep(dur!"msecs"(delayMilliseconds));
    }

    postMouseEvent(upEventType(button), position, button, clickState);
}

void mouseDoubleClick(int button, long delayMilliseconds)
{
    import core.thread.osthread : Thread;
    import core.time : dur;

    auto position = clickPosition();

    // Counted here rather than through nextClickState: `doubleclick` means a
    // double click whatever the timing, including under an x-set-delay longer
    // than the system's own interval.
    foreach (clickState; 1 .. 3)
    {
        postMouseEvent(downEventType(button), position, button, clickState);

        if (delayMilliseconds > 0)
        {
            Thread.sleep(dur!"msecs"(delayMilliseconds));
        }

        postMouseEvent(upEventType(button), position, button, clickState);
    }

    recordClickCount(button, position, 2);
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
    auto position = clickPosition();

    // A drag is its own gesture: a click after it starts a fresh count.
    lastClick = ClickCount.init;

    if (draggingButton.isNull)
    {
        postMouseEvent(downEventType(button), position, button, 1);
        draggingButton = button;
    }
    else
    {
        auto held = draggingButton.get();

        // Modifiers are applied to the mouse event itself rather than
        // synthesised as separate key presses.
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

// --- Focused window ---------------------------------------------------------

private CFStringRef cfString(string s)
{
    import std.string : toStringz;

    return CFStringCreateWithCString(null, s.toStringz, kCFStringEncodingUTF8);
}

/// Bounds of the focused window, for `windowzoom`. Uses the Accessibility API,
/// which reports the actually-focused window rather than guessing from the
/// on-screen window list.
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
