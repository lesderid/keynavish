//
// Objective-C shim for the macOS port of keynavish.
//
// D cannot practically drive AppKit: extern(Objective-C) has no properties,
// blocks, categories or protocol conformance, and no usable third-party binding
// exists (see MACOS-PORT.md §5.5). So everything that needs AppKit lives here
// and is exposed to D as a flat C API.
//
// Everything macOS offers as a C API already -- CoreGraphics event taps and
// event synthesis, display enumeration, the Accessibility API, UCKeyTranslate,
// CoreText -- is called directly from D and is deliberately NOT wrapped here.
//
// Build: clang -c -fobjc-arc -o build/shim.o src/keynavish/platform/macos/shim.m
//

#import <Cocoa/Cocoa.h>

// ---------------------------------------------------------------------------
// Callbacks into D
// ---------------------------------------------------------------------------

// Menu item activation. The tag matches keynavish.platform.macos.statusitem.MenuItem.
typedef void (*knv_menu_callback)(int tag);

// Asks D to paint the grid into a CGContext for the display at `displayIndex`.
// Rect is in the window's own top-left-origin coordinate space, in points.
typedef void (*knv_paint_callback)(int displayIndex, CGContextRef context,
                                   double width, double height);

// Display arrangement changed; D should rebuild its overlay windows.
typedef void (*knv_screens_changed_callback)(void);

// The selected keyboard layout changed; D must rebuild its key map, since key
// names are resolved against the active layout.
typedef void (*knv_layout_changed_callback)(void);

static knv_menu_callback            g_menu_callback;
static knv_paint_callback           g_paint_callback;
static knv_screens_changed_callback g_screens_changed_callback;
static knv_layout_changed_callback  g_layout_changed_callback;

// ---------------------------------------------------------------------------
// Application
// ---------------------------------------------------------------------------

@interface KnvAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation KnvAppDelegate
- (void)screensChanged:(NSNotification *)note
{
    (void)note;
    if (g_screens_changed_callback) g_screens_changed_callback();
}

- (void)layoutChanged:(NSNotification *)note
{
    (void)note;
    if (g_layout_changed_callback) g_layout_changed_callback();
}
@end

static KnvAppDelegate *g_app_delegate;

void knv_app_init(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        // Menu bar item only: no Dock icon, no app menu.
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        g_app_delegate = [[KnvAppDelegate alloc] init];
        [NSApp setDelegate:g_app_delegate];

        [[NSNotificationCenter defaultCenter]
            addObserver:g_app_delegate
               selector:@selector(screensChanged:)
                   name:NSApplicationDidChangeScreenParametersNotification
                 object:nil];

        // Key names resolve against the active layout, so switching layout has
        // to invalidate the map. See MACOS-PORT.md §6.3.
        [[NSNotificationCenter defaultCenter]
            addObserver:g_app_delegate
               selector:@selector(layoutChanged:)
                   name:NSTextInputContextKeyboardSelectionDidChangeNotification
                 object:nil];
    }
}

void knv_run(void)
{
    [NSApp run];
}

void knv_terminate(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
}

void knv_set_screens_changed_callback(knv_screens_changed_callback cb)
{
    g_screens_changed_callback = cb;
}

void knv_set_layout_changed_callback(knv_layout_changed_callback cb)
{
    g_layout_changed_callback = cb;
}

// ---------------------------------------------------------------------------
// Status item
// ---------------------------------------------------------------------------

// Rebuild the menu just before it is shown, so anything time-varying in it is
// current: whether another app is holding secure input, whether Accessibility
// has been granted, and the launch-at-login checkbox.
typedef void (*knv_menu_opening_callback)(void);
static knv_menu_opening_callback g_menu_opening_callback;

@interface KnvMenuTarget : NSObject <NSMenuDelegate>
@end

@implementation KnvMenuTarget
- (void)activate:(id)sender
{
    if (g_menu_callback) g_menu_callback((int)[(NSMenuItem *)sender tag]);
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    (void)menu;
    if (g_menu_opening_callback) g_menu_opening_callback();
}
@end

void knv_set_menu_opening_callback(knv_menu_opening_callback cb)
{
    g_menu_opening_callback = cb;
}

static NSStatusItem  *g_status_item;
static KnvMenuTarget *g_menu_target;
static NSMenu        *g_menu;

void knv_status_item_create(const char *symbol_name, const char *tooltip)
{
    @autoreleasepool {
        g_menu_target = [[KnvMenuTarget alloc] init];

        g_status_item = [[NSStatusBar systemStatusBar]
            statusItemWithLength:NSVariableStatusItemLength];

        NSString *name = [NSString stringWithUTF8String:symbol_name];
        NSImage *image = [NSImage imageWithSystemSymbolName:name
                                   accessibilityDescription:@"keynavish"];
        if (image)
        {
            // Template images adapt to light/dark menu bars automatically.
            [image setTemplate:YES];
            g_status_item.button.image = image;
        }
        else
        {
            // Symbol unavailable on this OS version; fall back to a title so the
            // item is at least present and clickable.
            g_status_item.button.title = @"kn";
        }

        g_status_item.button.toolTip = [NSString stringWithUTF8String:tooltip];

        g_menu = [[NSMenu alloc] init];
        [g_menu setAutoenablesItems:NO];
        g_menu.delegate = g_menu_target;
        g_status_item.menu = g_menu;
    }
}

void knv_status_item_set_attention(int attention)
{
    @autoreleasepool {
        if (!g_status_item) return;
        // Dim the icon while the app is not yet functional (no Accessibility
        // permission). See MACOS-PORT.md §7.1.
        g_status_item.button.appearsDisabled = attention ? YES : NO;
    }
}

void knv_menu_clear(void)
{
    @autoreleasepool {
        [g_menu removeAllItems];
    }
}

void knv_menu_add_item(const char *title, int tag, int checked, int enabled)
{
    @autoreleasepool {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:[NSString stringWithUTF8String:title]
                   action:@selector(activate:)
            keyEquivalent:@""];
        item.target = g_menu_target;
        item.tag = tag;
        item.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
        item.enabled = enabled ? YES : NO;
        [g_menu addItem:item];
    }
}

void knv_menu_add_separator(void)
{
    @autoreleasepool {
        [g_menu addItem:[NSMenuItem separatorItem]];
    }
}

void knv_set_menu_callback(knv_menu_callback cb)
{
    g_menu_callback = cb;
}

// ---------------------------------------------------------------------------
// Displays
// ---------------------------------------------------------------------------

//
// Display enumeration goes through NSScreen rather than CGGetActiveDisplayList.
// The CoreGraphics call is documented for exactly this and needs no permission,
// but it reports zero active displays on at least macOS 26 while NSScreen
// correctly reports them, so it cannot be relied on.
//
// Using NSScreen also removes an ordering hazard: the overlay windows are
// positioned against NSScreen, so enumerating with the same API guarantees
// index i here means the same display as index i there.
//
// Results are converted to the Quartz global display space (top-left origin,
// Y down) to match keynavish's own coordinate convention. See MACOS-PORT.md §6.1.
//

int knv_display_count(void)
{
    @autoreleasepool {
        return (int) [NSScreen screens].count;
    }
}

// Writes left, top, right, bottom (Quartz coordinates, points) into outRect.
void knv_display_bounds(int index, double *outRect)
{
    @autoreleasepool {
        NSArray<NSScreen *> *screens = [NSScreen screens];
        if (index < 0 || index >= (int) screens.count || !outRect) return;

        CGFloat primaryTop = NSMaxY(screens[0].frame);
        NSRect frame = screens[index].frame;

        double top = primaryTop - NSMaxY(frame);

        outRect[0] = frame.origin.x;
        outRect[1] = top;
        outRect[2] = frame.origin.x + frame.size.width;
        outRect[3] = top + frame.size.height;
    }
}

// ---------------------------------------------------------------------------
// Overlay windows
// ---------------------------------------------------------------------------

//
// One borderless window per display, rather than a single window spanning the
// virtual screen as on Windows: with "Displays have separate Spaces" (the
// default) a window cannot span displays usefully. See MACOS-PORT.md §6.4.
//

@interface KnvOverlayView : NSView
@property (assign) int displayIndex;
@end

@implementation KnvOverlayView

// A flipped view gives drawRect: a top-left-origin, Y-down CGContext, which is
// exactly keynavish's own coordinate convention -- so no CTM juggling, and the
// grid rectangles can be drawn as-is. Text still needs its own flip, handled in
// the D drawing code's text matrix.
- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    if (!g_paint_callback) return;

    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    NSRect bounds = self.bounds;

    g_paint_callback(self.displayIndex, context, bounds.size.width, bounds.size.height);
}

@end

static NSMutableArray<NSWindow *> *g_overlay_windows;

void knv_set_paint_callback(knv_paint_callback cb)
{
    g_paint_callback = cb;
}

void knv_overlay_destroy(void)
{
    @autoreleasepool {
        for (NSWindow *window in g_overlay_windows)
        {
            [window orderOut:nil];
            [window close];
        }
        g_overlay_windows = nil;
    }
}

// `rects` is 4 doubles per display -- left, top, right, bottom -- in the Quartz
// global display space (top-left origin, Y down). Converted to AppKit's
// bottom-left origin here, which is the only place that conversion happens.
void knv_overlay_create(int count, const double *rects)
{
    @autoreleasepool {
        knv_overlay_destroy();

        g_overlay_windows = [NSMutableArray array];

        NSArray<NSScreen *> *screens = [NSScreen screens];
        if (screens.count == 0) return;

        // AppKit's origin is the bottom-left of the screen at index 0.
        CGFloat primaryTop = NSMaxY(screens[0].frame);

        for (int i = 0; i < count; i++)
        {
            double left   = rects[i * 4 + 0];
            double top    = rects[i * 4 + 1];
            double right  = rects[i * 4 + 2];
            double bottom = rects[i * 4 + 3];

            CGFloat width  = right - left;
            CGFloat height = bottom - top;

            NSRect frame = NSMakeRect(left, primaryTop - (top + height), width, height);

            NSWindow *window =
                [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskBorderless
                                              backing:NSBackingStoreBuffered
                                                defer:NO];

            // Real alpha -- no colour-key hack needed, unlike the Windows build.
            window.opaque = NO;
            window.backgroundColor = [NSColor clearColor];
            window.hasShadow = NO;

            // Never take input: keynavish's overlay is purely decorative, all
            // interaction goes through the event tap.
            window.ignoresMouseEvents = YES;

            // Above everything, including captured displays. See §6.4.
            window.level = CGShieldingWindowLevel();

            window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                      | NSWindowCollectionBehaviorStationary
                                      | NSWindowCollectionBehaviorFullScreenAuxiliary
                                      | NSWindowCollectionBehaviorIgnoresCycle;

            // Don't participate in window restoration or the window menu.
            window.excludedFromWindowsMenu = YES;
            [window setRestorable:NO];

            // Programmatically created NSWindows default to releasedWhenClosed
            // YES, which pairs badly with the strong reference held in
            // g_overlay_windows. 200 create/destroy cycles did not actually
            // misbehave without this, so it is hardening rather than a fix for
            // an observed crash -- but relying on that is not worth it.
            window.releasedWhenClosed = NO;

            KnvOverlayView *view = [[KnvOverlayView alloc] initWithFrame:frame];
            view.displayIndex = i;
            window.contentView = view;

            [g_overlay_windows addObject:window];
        }
    }
}

void knv_overlay_show(void)
{
    @autoreleasepool {
        for (NSWindow *window in g_overlay_windows)
        {
            // orderFrontRegardless, not makeKeyAndOrderFront: the overlay must
            // never steal focus from whatever the user is actually working in.
            [window orderFrontRegardless];
            [window.contentView setNeedsDisplay:YES];
        }
    }
}

void knv_overlay_hide(void)
{
    @autoreleasepool {
        for (NSWindow *window in g_overlay_windows)
        {
            [window orderOut:nil];
        }
    }
}

void knv_overlay_redraw(void)
{
    @autoreleasepool {
        for (NSWindow *window in g_overlay_windows)
        {
            [window.contentView setNeedsDisplay:YES];
        }
    }
}

int knv_overlay_count(void)
{
    return (int) g_overlay_windows.count;
}

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------

// Presented on the main queue rather than synchronously: a modal alert raised
// from inside the CGEventTap callback would block the run loop and get the tap
// disabled by timeout. See MACOS-PORT.md §6.12.
static void knv_alert(const char *message, NSAlertStyle style)
{
    NSString *text = [NSString stringWithUTF8String:message];
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"keynavish";
            alert.informativeText = text;
            alert.alertStyle = style;
            [alert runModal];
        }
    });
}

// Synchronous three-button prompt, returning 0/1/2 for the buttons in order.
//
// Unlike the alerts above this one blocks, which is safe ONLY because it is
// reached from a menu action on the main thread. It must never be called from
// the event tap callback -- see MACOS-PORT.md 6.12.
int knv_alert_choice(const char *message, const char *button0,
                     const char *button1, const char *button2)
{
    @autoreleasepool {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"keynavish";
        alert.informativeText = [NSString stringWithUTF8String:message];
        alert.alertStyle = NSAlertStyleInformational;

        [alert addButtonWithTitle:[NSString stringWithUTF8String:button0]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:button1]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:button2]];

        [NSApp activateIgnoringOtherApps:YES];

        return (int)([alert runModal] - NSAlertFirstButtonReturn);
    }
}

void knv_alert_error(const char *message)   { knv_alert(message, NSAlertStyleCritical); }
void knv_alert_warning(const char *message) { knv_alert(message, NSAlertStyleWarning); }
void knv_alert_info(const char *message)    { knv_alert(message, NSAlertStyleInformational); }

// ---------------------------------------------------------------------------
// Opening files and URLs
// ---------------------------------------------------------------------------

void knv_open_url(const char *url)
{
    @autoreleasepool {
        NSURL *nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:url]];
        if (nsurl) [[NSWorkspace sharedWorkspace] openURL:nsurl];
    }
}

void knv_open_file(const char *path)
{
    @autoreleasepool {
        NSURL *nsurl = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
        if (nsurl) [[NSWorkspace sharedWorkspace] openURL:nsurl];
    }
}

// Path to the .app bundle's Contents/Resources, or NULL when running unbundled.
// Caller must not free; the string is owned by the autoreleased NSString's
// backing store, so it is copied into a static buffer.
static char g_resource_path[PATH_MAX];

const char *knv_resource_path(void)
{
    @autoreleasepool {
        NSString *path = [[NSBundle mainBundle] resourcePath];
        if (!path) return NULL;
        if (![path getCString:g_resource_path
                    maxLength:sizeof(g_resource_path)
                     encoding:NSUTF8StringEncoding])
        {
            return NULL;
        }
        return g_resource_path;
    }
}

static char g_bundle_path[PATH_MAX];

const char *knv_bundle_path(void)
{
    @autoreleasepool {
        NSString *path = [[NSBundle mainBundle] bundlePath];
        if (!path) return NULL;
        if (![path getCString:g_bundle_path
                    maxLength:sizeof(g_bundle_path)
                     encoding:NSUTF8StringEncoding])
        {
            return NULL;
        }
        return g_bundle_path;
    }
}

const char *knv_home_directory(void)
{
    @autoreleasepool {
        static char home[PATH_MAX];
        NSString *path = NSHomeDirectory();
        if (!path) return NULL;
        if (![path getCString:home maxLength:sizeof(home) encoding:NSUTF8StringEncoding])
        {
            return NULL;
        }
        return home;
    }
}

// ---------------------------------------------------------------------------
// Accessibility permission
// ---------------------------------------------------------------------------

#import <ApplicationServices/ApplicationServices.h>

// Shows the system's own "wants to control this computer" prompt, and reports
// whether the process is already trusted.
//
// Done here rather than in D because building the options dictionary needs
// kAXTrustedCheckOptionPrompt and kCFBooleanTrue; a literal NSDictionary is far
// less error-prone than the equivalent CoreFoundation calls.
int knv_request_accessibility_permission(void)
{
    @autoreleasepool {
        NSDictionary *options = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
        return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options) ? 1 : 0;
    }
}

// ---------------------------------------------------------------------------
// Deferred work
// ---------------------------------------------------------------------------

typedef void (*knv_async_callback)(void);

// Runs a callback on the main queue after the current work finishes. Used to
// tear down and rebuild the event tap from outside the tap's own callback,
// which must not block or destroy the port it is running on.
void knv_dispatch_async(knv_async_callback cb)
{
    if (!cb) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        cb();
    });
}

// ---------------------------------------------------------------------------
// Timers
// ---------------------------------------------------------------------------

typedef void (*knv_timer_callback)(void);

static NSTimer *g_timer;

// Used to poll for the Accessibility grant so the app starts working the moment
// the user flips the switch, with no restart. See MACOS-PORT.md §7.1.
void knv_schedule_timer(double intervalSeconds, knv_timer_callback cb)
{
    @autoreleasepool {
        [g_timer invalidate];
        g_timer = [NSTimer scheduledTimerWithTimeInterval:intervalSeconds
                                                  repeats:YES
                                                    block:^(NSTimer *timer) {
            (void)timer;
            if (cb) cb();
        }];
    }
}

void knv_cancel_timer(void)
{
    @autoreleasepool {
        [g_timer invalidate];
        g_timer = nil;
    }
}

// ---------------------------------------------------------------------------
// Launch at login
// ---------------------------------------------------------------------------

#import <ServiceManagement/ServiceManagement.h>

int knv_login_item_enabled(void)
{
    if (@available(macOS 13.0, *))
    {
        return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
    }
    return 0;
}

int knv_login_item_set(int enabled)
{
    if (@available(macOS 13.0, *))
    {
        NSError *error = nil;
        BOOL ok = enabled
            ? [SMAppService.mainAppService registerAndReturnError:&error]
            : [SMAppService.mainAppService unregisterAndReturnError:&error];
        return ok ? 1 : 0;
    }
    return 0;
}
