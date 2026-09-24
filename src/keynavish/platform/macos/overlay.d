module keynavish.platform.macos.overlay;

version (OSX):

import keynavish;
import keynavish.types;
import keynavish.platform.macos.shim;
import keynavish.platform.macos.coregraphics;
import keynavish.platform.macos.coretext;
import keynavish.platform.macos.display;

//
// One borderless overlay window per display, with the grid drawn from D via
// CoreGraphics/CoreText. The Objective-C shim owns the NSWindows and calls back
// into paintCallback below.
//

alias Canvas = CGContextRef;

struct TextSize
{
    int width;
    int height;
}

bool active;
bool quitting;

/// Global-coordinate origin of each overlay window, indexed the same way as
/// displayRectangles. Captured when the windows are created so the paint
/// callback can translate global grid coordinates into window-local ones.
private Rect[] overlayRects;

void createWindow()
{
    knv_set_paint_callback(&paintCallback);
    knv_set_screens_changed_callback(&screensChangedCallback);

    rebuildOverlayWindows();
}

private void rebuildOverlayWindows()
{
    overlayRects = displayRectangles;

    double[] flat;
    flat.reserve(overlayRects.length * 4);
    foreach (rect; overlayRects)
    {
        flat ~= [cast(double) rect.left, cast(double) rect.top,
                 cast(double) rect.right, cast(double) rect.bottom];
    }

    knv_overlay_create(cast(int) overlayRects.length, flat.ptr);

    if (active)
    {
        knv_overlay_show();
    }
}

extern (C) void screensChangedCallback() nothrow
{
    // The display arrangement changed: rebuild the windows so the overlay keeps
    // covering every screen. Grid state is left alone; the next start() resets
    // it anyway.
    try
    {
        rebuildOverlayWindows();
    }
    catch (Throwable)
    {
    }
}

void showWindow()
{
    active = true;

    knv_overlay_show();
}

void hideWindow()
{
    active = false;

    knv_overlay_hide();
}

void redrawWindow()
{
    knv_overlay_redraw();
}

/// Called by the shim from the overlay view's drawRect:.
extern (C) void paintCallback(int displayIndex, void* context, double width, double height) nothrow
{
    try
    {
        if (displayIndex < 0 || displayIndex >= overlayRects.length) return;

        auto origin = Point(overlayRects[displayIndex].left, overlayRects[displayIndex].top);

        paintGrid(cast(Canvas) context, origin);
    }
    catch (Throwable)
    {
        // Never let an exception escape into AppKit's drawing machinery.
    }
}

//
// Drawing primitives used by the shared paintGrid in grid.d.
//

private CGColorSpaceRef deviceColourSpace()
{
    static CGColorSpaceRef cached;

    if (cached is null)
    {
        cached = CGColorSpaceCreateDeviceRGB();
    }

    return cached;
}

private CGColorRef makeColour(uint colour)
{
    // Device RGB, not CGColorCreateGenericRGB: generic RGB is colour-managed on
    // its way to the display, which shifts the values away from the Windows
    // build's -- RGB(30,64,64) came out as (38,81,81).
    CGFloat[4] components = [colour.redOf / 255.0,
                             colour.greenOf / 255.0,
                             colour.blueOf / 255.0,
                             1.0];

    return CGColorCreate(deviceColourSpace(), components.ptr);
}

private CGRect toCGRect(Rect rect)
{
    return CGRect(CGPoint(rect.left, rect.top),
                  CGSize(rect.width, rect.height));
}

void strokeRectangles(Canvas canvas, const(Rect)[] rects, uint colour, int lineWidth)
{
    auto cgColour = makeColour(colour);
    scope (exit) CGColorRelease(cgColour);

    CGContextSaveGState(canvas);
    scope (exit) CGContextRestoreGState(canvas);

    CGContextSetStrokeColorWithColor(canvas, cgColour);
    CGContextSetLineWidth(canvas, lineWidth);

    CGContextBeginPath(canvas);
    foreach (rect; rects)
    {
        // Half-pixel offset so a 1pt stroke lands on a pixel boundary rather
        // than straddling two and rendering blurry.
        auto r = rect.toCGRect;
        r.origin.x += 0.5;
        r.origin.y += 0.5;
        CGContextAddRect(canvas, r);
    }
    CGContextStrokePath(canvas);
}

void fillRectangle(Canvas canvas, Rect rect, uint colour)
{
    auto cgColour = makeColour(colour);
    scope (exit) CGColorRelease(cgColour);

    CGContextSaveGState(canvas);
    scope (exit) CGContextRestoreGState(canvas);

    CGContextSetFillColorWithColor(canvas, cgColour);
    CGContextFillRect(canvas, rect.toCGRect);
}

private enum labelFontName = "Menlo-Bold";
private enum labelFontSize = 18.0;

private CTFontRef labelFont()
{
    static CTFontRef cached;

    if (cached is null)
    {
        auto name = CFStringCreateWithCString(null, labelFontName, kCFStringEncodingUTF8);
        scope (exit) if (name !is null) CFRelease(name);

        cached = CTFontCreateWithName(name, labelFontSize, null);
    }

    return cached;
}

private CTLineRef makeLine(const(char)[] text, uint colour)
{
    import std.string : toStringz;

    auto cfText = CFStringCreateWithCString(null, text.toStringz, kCFStringEncodingUTF8);
    if (cfText is null) return null;
    scope (exit) CFRelease(cfText);

    auto cgColour = makeColour(colour);
    scope (exit) CGColorRelease(cgColour);

    const(void)*[2] keys = [cast(const(void)*) kCTFontAttributeName,
                            cast(const(void)*) kCTForegroundColorAttributeName];
    const(void)*[2] values = [cast(const(void)*) labelFont(),
                              cast(const(void)*) cgColour];

    auto attributes = CFDictionaryCreate(null, keys.ptr, values.ptr, 2,
                                         &kCFTypeDictionaryKeyCallBacks,
                                         &kCFTypeDictionaryValueCallBacks);
    if (attributes is null) return null;
    scope (exit) CFRelease(attributes);

    auto attributed = CFAttributedStringCreate(null, cfText, attributes);
    if (attributed is null) return null;
    scope (exit) CFRelease(attributed);

    return CTLineCreateWithAttributedString(attributed);
}

TextSize measureLabel(Canvas canvas, const(char)[] text)
{
    import std.math : round;

    auto line = makeLine(text, 0xFFFFFF);
    if (line is null) return TextSize(0, 0);
    scope (exit) CFRelease(line);

    CGFloat ascent, descent, leading;
    auto width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);

    return TextSize(cast(int) round(width), cast(int) round(ascent + descent));
}

void drawLabel(Canvas canvas, int x, int y, const(char)[] text, uint colour)
{
    auto line = makeLine(text, colour);
    if (line is null) return;
    scope (exit) CFRelease(line);

    CGFloat ascent, descent, leading;
    CTLineGetTypographicBounds(line, &ascent, &descent, &leading);

    CGContextSaveGState(canvas);
    scope (exit) CGContextRestoreGState(canvas);

    // The overlay view is flipped (top-left origin, Y down) to match the grid
    // coordinate convention, so the text matrix has to be flipped back or the
    // glyphs render upside down.
    CGContextSetTextMatrix(canvas, CGAffineTransform(1, 0, 0, -1, 0, 0));

    // y is the top of the text box; CoreText draws from the baseline.
    CGContextSetTextPosition(canvas, x, y + ascent);

    CTLineDraw(line, canvas);
}

void quitApplication()
{
    quitting = true;

    knv_terminate();
}
