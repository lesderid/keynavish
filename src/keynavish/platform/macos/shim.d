module keynavish.platform.macos.shim;

version (OSX):

//
// Declarations for the Objective-C shim (shim.m).
//
// Only AppKit-dependent functionality lives behind the shim. CoreGraphics,
// the Accessibility API, UCKeyTranslate and CoreText are plain C and are bound
// directly in the modules that use them.
//

import core.stdc.config : c_long;

extern (C):
nothrow:

alias MenuCallback = extern (C) void function(int tag);
alias PaintCallback = extern (C) void function(int displayIndex, void* context,
                                               double width, double height);
alias ScreensChangedCallback = extern (C) void function();
alias LayoutChangedCallback = extern (C) void function();

// Application lifecycle
void knv_app_init();
void knv_run();
void knv_terminate();
void knv_set_screens_changed_callback(ScreensChangedCallback cb);
void knv_set_layout_changed_callback(LayoutChangedCallback cb);

// Displays (NSScreen; CGGetActiveDisplayList is unreliable, see shim.m)
int knv_display_count();
void knv_display_bounds(int index, double* outRect);

// Overlay windows
void knv_set_paint_callback(PaintCallback cb);
void knv_overlay_create(int count, const(double)* rects);
void knv_overlay_destroy();
void knv_overlay_show();
void knv_overlay_hide();
void knv_overlay_redraw();
int knv_overlay_count();

// Status item
void knv_status_item_create(const(char)* symbolName, const(char)* tooltip);
void knv_status_item_set_attention(int attention);
void knv_menu_clear();
void knv_menu_add_item(const(char)* title, int tag, int checked, int enabled);
void knv_menu_add_separator();
void knv_set_menu_callback(MenuCallback cb);

// Alerts (presented asynchronously on the main queue)
void knv_alert_error(const(char)* message);
void knv_alert_warning(const(char)* message);
void knv_alert_info(const(char)* message);

/// Synchronous three-button prompt; returns the zero-based button index.
/// Main thread only -- never from the event tap callback.
int knv_alert_choice(const(char)* message, const(char)* button0,
                     const(char)* button1, const(char)* button2);

// Opening files and URLs
void knv_open_url(const(char)* url);
void knv_open_file(const(char)* path);

// Bundle and filesystem locations
const(char)* knv_resource_path();
const(char)* knv_bundle_path();
const(char)* knv_home_directory();

// Timers (used to poll for the Accessibility grant, §7.1)
alias TimerCallback = extern (C) void function();
void knv_schedule_timer(double intervalSeconds, TimerCallback cb);
void knv_cancel_timer();

// Launch at login (SMAppService, macOS 13+)
int knv_login_item_enabled();
int knv_login_item_set(int enabled);
