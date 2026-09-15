//
// Offscreen render test for the macOS drawing path.
//
// The overlay can't be inspected visually from a headless build, so this
// renders paintGrid into a CGBitmapContext and asserts on the resulting pixels.
// It covers the parts most likely to be silently wrong: the grid geometry from
// splitGrid, the global-to-window coordinate translation, and the grid-nav
// label placement.
//
// Build and run: tools/run-render-test.sh
//
module render_test;

version (OSX):

import core.stdc.stdio : printf;
import keynavish;
import keynavish.types;
import keynavish.platform.macos.coregraphics;
import keynavish.platform.macos.coretext;
import keynavish.platform.macos.overlay;

enum testWidth = 400;
enum testHeight = 300;

private ubyte[] pixels;
private CGContextRef context;

private void makeContext()
{
    pixels = new ubyte[testWidth * testHeight * 4];

    auto colourSpace = CGColorSpaceCreateDeviceRGB();
    scope (exit) CGColorSpaceRelease(colourSpace);

    context = CGBitmapContextCreate(pixels.ptr, testWidth, testHeight, 8, testWidth * 4,
                                    colourSpace, kCGImageAlphaPremultipliedLast);

    assert(context !is null, "could not create bitmap context");

    // Match the flipped, top-left-origin coordinate space the overlay view
    // gives drawRect:, so the test exercises the same geometry as the real path.
    CGContextTranslateCTM(context, 0, testHeight);
    CGContextScaleCTM(context, 1, -1);
}

private struct Pixel
{
    ubyte r, g, b, a;

    string toString() const
    {
        import std.format : format;
        return format!"(%d,%d,%d,%d)"(r, g, b, a);
    }
}

private Pixel pixelAt(int x, int y)
{
    auto offset = (y * testWidth + x) * 4;
    return Pixel(pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3]);
}

private bool isBlank(Pixel p)
{
    return p.a == 0;
}

private int countNonBlank()
{
    int count;
    foreach (y; 0 .. testHeight)
    {
        foreach (x; 0 .. testWidth)
        {
            if (!pixelAt(x, y).isBlank) count++;
        }
    }
    return count;
}

private void check(string name, bool condition)
{
    import std.string : toStringz;

    printf("%s %s\n", condition ? "  PASS".ptr : "  FAIL".ptr, name.toStringz);
    if (!condition) failures++;
}

private int failures;

void main()
{
    printf("macOS render test\n");

    makeContext();

    // A 2x2 grid covering the whole test surface, positioned at a non-zero
    // global origin so the translation is actually exercised.
    enum originX = 1000;
    enum originY = 500;

    grid = Grid(Rect(originX, originY, originX + testWidth, originY + testHeight), 2, 2);

    printf("\ngrid lines\n");

    paintGrid(context, Point(originX, originY));

    auto painted = countNonBlank();
    check("something was drawn", painted > 0);

    // The 2x2 split puts interior lines at the halfway points, and the border
    // strokes run along the outer edges.
    check("vertical centre line drawn", !pixelAt(testWidth / 2, testHeight / 2).isBlank);
    check("horizontal centre line drawn", !pixelAt(testWidth / 4, testHeight / 2).isBlank);
    check("left edge drawn", !pixelAt(0, testHeight / 2).isBlank);
    check("top edge drawn", !pixelAt(testWidth / 2, 0).isBlank);

    // Cell interiors must stay clear, or the overlay would obscure the screen.
    check("cell interior is transparent", pixelAt(testWidth / 4, testHeight / 4).isBlank);
    check("overlay is mostly transparent", painted < (testWidth * testHeight) / 4);

    // The narrow dark main pen is stroked over the wide light border pen, so
    // the centre of a grid line should be the main pen colour.
    auto centre = pixelAt(testWidth / 2, testHeight / 4);
    check("grid line centre uses main pen colour",
          centre.r == mainPenColour.redOf
          && centre.g == mainPenColour.greenOf
          && centre.b == mainPenColour.blueOf);

    printf("\ngrid-nav labels\n");

    pixels[] = 0;
    enableGridNav(true);
    paintGrid(context, Point(originX, originY));

    auto withLabels = countNonBlank();
    check("labels add drawn pixels", withLabels > painted);

    // Each cell centre should now carry a label background.
    auto labelPixel = pixelAt(testWidth / 4, testHeight / 4);
    check("label background drawn at cell centre",
          labelPixel.r == gridNavLabelColour.redOf
          && labelPixel.g == gridNavLabelColour.greenOf
          && labelPixel.b == gridNavLabelColour.blueOf);

    // Selecting a row must recolour that row's labels and leave the other alone.
    pixels[] = 0;
    gridNavState = GridNavState.column;
    gridNavRow = 0;
    paintGrid(context, Point(originX, originY));

    auto selected = pixelAt(testWidth / 4, testHeight / 4);
    check("selected row uses the highlight colour",
          selected.r == gridNavLabelSelectedColour.redOf
          && selected.g == gridNavLabelSelectedColour.greenOf
          && selected.b == gridNavLabelSelectedColour.blueOf);

    auto unselected = pixelAt(testWidth / 4, testHeight * 3 / 4);
    check("unselected row keeps the normal colour",
          unselected.r == gridNavLabelColour.redOf
          && unselected.g == gridNavLabelColour.greenOf
          && unselected.b == gridNavLabelColour.blueOf);

    printf("\nlabel text\n");

    auto textSize = context.measureLabel("AA");
    check("label text measures non-zero", textSize.width > 0 && textSize.height > 0);

    // The overlay view is flipped, so drawLabel has to flip the text matrix
    // back. Measuring alone would not catch getting that wrong: the glyphs
    // would still measure the same while rendering upside down, mirrored about
    // the baseline and therefore ABOVE the requested y. So draw in isolation and
    // assert where the ink actually lands.
    pixels[] = 0;

    enum textX = 100;
    enum textY = 100;

    context.drawLabel(textX, textY, "AA", gridNavTextColour);

    int inkInside;
    int inkOutside;

    foreach (y; 0 .. testHeight)
    {
        foreach (x; 0 .. testWidth)
        {
            if (pixelAt(x, y).isBlank) continue;

            if (x >= textX && x <= textX + textSize.width
                && y >= textY && y <= textY + textSize.height)
            {
                inkInside++;
            }
            else
            {
                inkOutside++;
            }
        }
    }

    check("label text actually draws ink", inkInside > 0);

    // Verified to fail when the text matrix flip in drawLabel is removed.
    check("all label ink lands inside the label box", inkOutside == 0);

    printf("\n%s\n", failures == 0 ? "all checks passed".ptr : "FAILURES PRESENT".ptr);

    CGContextRelease(context);

    import core.stdc.stdlib : exit;
    exit(failures == 0 ? 0 : 1);
}
