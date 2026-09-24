module keynavish.platform.macos.display;

version (OSX):

import keynavish.types;
import keynavish.helpers : width, height;
import keynavish.platform.macos.coregraphics;
import keynavish.platform.macos.shim;

//
// Display enumeration and cursor position, in the Quartz global display space:
// origin at the top-left of the main display, Y growing downward.
//
// Everything here is in points, not pixels: Retina backing scale is handled by
// AppKit at draw time and must not leak into the grid maths.
//

@property
Rect[] displayRectangles()
{
    import std.math : round;

    auto count = knv_display_count();

    Rect[] rectangles;
    rectangles.reserve(count);

    foreach (index; 0 .. count)
    {
        double[4] bounds;
        knv_display_bounds(index, bounds.ptr);

        rectangles ~= Rect(cast(int) round(bounds[0]),
                           cast(int) round(bounds[1]),
                           cast(int) round(bounds[2]),
                           cast(int) round(bounds[3]));
    }

    return rectangles;
}

@property
Rect virtualScreenRectangle()
{
    import std.algorithm : max, min;

    auto rectangles = displayRectangles;

    if (rectangles.length == 0)
    {
        return Rect(0, 0, 0, 0);
    }

    auto result = rectangles[0];
    foreach (rectangle; rectangles[1 .. $])
    {
        result.left   = min(result.left, rectangle.left);
        result.top    = min(result.top, rectangle.top);
        result.right  = max(result.right, rectangle.right);
        result.bottom = max(result.bottom, rectangle.bottom);
    }

    return result;
}

@property
Point cursorPosition()
{
    import std.math : round;

    auto event = CGEventCreate(null);
    if (event is null)
    {
        return Point(0, 0);
    }
    scope (exit) CFRelease(event);

    auto location = CGEventGetLocation(event);

    return Point(cast(int) round(location.x), cast(int) round(location.y));
}
