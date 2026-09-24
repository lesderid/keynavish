//
// Grid arithmetic tests.
//
// cut, move, cell-select and the grid stack are the behaviour users actually
// feel, and they are shared verbatim between platforms -- so a regression here
// would silently change what the same keynavrc does. Pure integer maths with no
// platform dependency, which makes it the easiest thing in the project to pin
// down.
//
// Build and run: tools/run-tests.sh grid
//
module grid_test;

import core.stdc.stdio : printf;
import std.string : toStringz;
import keynavish;
import keynavish.types;

private int failures;
private int checks;
private int skipped;

private void skip(string name, string reason)
{
    skipped++;
    printf("  SKIP %s (%s)\n", name.toStringz, reason.toStringz);
}

private void check(string name, bool condition)
{
    checks++;
    printf("%s %s\n", condition ? "  PASS".ptr : "  FAIL".ptr, name.toStringz);
    if (!condition) failures++;
}

private void checkRect(string name, Rect got, Rect expected)
{
    checks++;

    auto ok = got == expected;
    printf("%s %s\n", ok ? "  PASS".ptr : "  FAIL".ptr, name.toStringz);
    if (!ok)
    {
        printf("       got      (%d,%d)-(%d,%d)\n", got.left, got.top, got.right, got.bottom);
        printf("       expected (%d,%d)-(%d,%d)\n",
               expected.left, expected.top, expected.right, expected.bottom);
        failures++;
    }
}

// A grid occupying a clean 1000x1000 area, so halving stays exact.
private void setGrid(int left, int top, int right, int bottom, int columns = 2, int rows = 2)
{
    grid = Grid(Rect(left, top, right, bottom), rows, columns);
}

void main()
{
    printf("grid arithmetic test\n");

    // cut/move are no-ops unless the overlay is active.
    active = true;

    printf("\ncut halves the grid by default\n");

    setGrid(0, 0, 1000, 1000);
    processCommand(["cut-left"]);
    checkRect("cut-left halves to the left", grid.rect, Rect(0, 0, 500, 1000));

    setGrid(0, 0, 1000, 1000);
    processCommand(["cut-right"]);
    checkRect("cut-right halves to the right", grid.rect, Rect(500, 0, 1000, 1000));

    setGrid(0, 0, 1000, 1000);
    processCommand(["cut-up"]);
    checkRect("cut-up halves upward", grid.rect, Rect(0, 0, 1000, 500));

    setGrid(0, 0, 1000, 1000);
    processCommand(["cut-down"]);
    checkRect("cut-down halves downward", grid.rect, Rect(0, 500, 1000, 1000));

    printf("\ncut with an explicit argument\n");

    // A fractional argument is a proportion of the current size.
    setGrid(0, 0, 1000, 1000);
    processCommand(["cut-left", "0.25"]);
    checkRect("cut-left 0.25 keeps a quarter", grid.rect, Rect(0, 0, 250, 1000));

    // An integer argument is an absolute pixel size.
    setGrid(0, 0, 1000, 1000);
    processCommand(["cut-right", "200"]);
    checkRect("cut-right 200 keeps 200px", grid.rect, Rect(800, 0, 1000, 1000));

    printf("\nrepeated cuts compose\n");

    setGrid(0, 0, 1000, 1000);
    processCommand(["cut-left"]);
    processCommand(["cut-up"]);
    checkRect("cut-left then cut-up reaches the top-left quarter",
              grid.rect, Rect(0, 0, 500, 500));

    printf("\nmove shifts without resizing\n");

    // move clamps the grid to the virtual screen, so these need real display
    // bounds. Headless environments (CI, a sandboxed shell) report none, and
    // everything would clamp against a 0x0 screen.
    auto screen = virtualScreenRectangle;
    auto haveDisplays = !screen.isEmpty;

    if (!haveDisplays)
    {
        skip("move tests", "no displays available in this environment");
    }
    else
    {
        // Keep well inside the screen so clamping is not what is under test.
        auto left = screen.left + 100;
        auto top = screen.top + 100;

        setGrid(left, top, left + 200, top + 200);
        auto beforeWidth = grid.rect.width;
        auto beforeHeight = grid.rect.height;

        processCommand(["move-right", "50"]);
        check("move-right shifts by 50",
              grid.rect.left == left + 50 && grid.rect.right == left + 250);
        check("move preserves size",
              grid.rect.width == beforeWidth && grid.rect.height == beforeHeight);

        setGrid(left, top, left + 200, top + 200);
        processCommand(["move-down", "50"]);
        check("move-down shifts by 50",
              grid.rect.top == top + 50 && grid.rect.bottom == top + 250);

        // Moving hard against an edge must clamp rather than leave the screen.
        setGrid(screen.left, screen.top, screen.left + 200, screen.top + 200);
        processCommand(["move-left", "10000"]);
        check("move-left clamps at the left edge", grid.rect.left == screen.left);
        check("clamping preserves size", grid.rect.width == 200);
    }

    printf("\ngrid stack (history-back)\n");

    setGrid(0, 0, 1000, 1000);
    processCommand(["cut-left"]);
    processCommand(["cut-up"]);
    checkRect("two cuts applied", grid.rect, Rect(0, 0, 500, 500));

    processCommand(["history-back"]);
    checkRect("history-back undoes the last cut", grid.rect, Rect(0, 0, 500, 1000));

    processCommand(["history-back"]);
    checkRect("history-back undoes the first cut", grid.rect, Rect(0, 0, 1000, 1000));

    printf("\ngrid dimensions and cell-select\n");

    setGrid(0, 0, 1000, 1000);
    processCommand(["grid", "4x4"]);
    check("grid 4x4 sets columns and rows", grid.columns == 4 && grid.rows == 4);

    // cell-select takes 1-based column x row.
    setGrid(0, 0, 1000, 1000, 4, 4);
    processCommand(["cell-select", "1x1"]);
    checkRect("cell-select 1x1 picks the top-left cell", grid.rect, Rect(0, 0, 250, 250));

    setGrid(0, 0, 1000, 1000, 4, 4);
    processCommand(["cell-select", "4x4"]);
    checkRect("cell-select 4x4 picks the bottom-right cell",
              grid.rect, Rect(750, 750, 1000, 1000));

    setGrid(0, 0, 1000, 1000, 4, 4);
    processCommand(["cell-select", "2x3"]);
    checkRect("cell-select 2x3 picks column 2, row 3", grid.rect, Rect(250, 500, 500, 750));

    printf("\nnon-square grids\n");

    setGrid(0, 0, 900, 600, 3, 2);
    processCommand(["cell-select", "3x1"]);
    checkRect("cell-select on a 3x2 grid", grid.rect, Rect(600, 0, 900, 300));

    printf("\ngrid-nav labels\n");

    check("row 0, column 0 labels AA", gridNavLabel(0, 0) == "AA");
    check("row 1, column 0 labels BA", gridNavLabel(1, 0) == "BA");
    check("row 0, column 2 labels AC", gridNavLabel(0, 2) == "AC");

    printf("\ncut is inert while inactive\n");

    active = false;
    setGrid(0, 0, 1000, 1000);
    processCommand(["cut-left"]);
    checkRect("cut does nothing when not active", grid.rect, Rect(0, 0, 1000, 1000));
    active = true;

    printf("\n%d checks, %d failures, %d skipped\n", checks, failures, skipped);
    printf("%s\n", failures == 0 ? "all checks passed".ptr : "FAILURES PRESENT".ptr);

    import core.stdc.stdlib : exit;
    exit(failures == 0 ? 0 : 1);
}
