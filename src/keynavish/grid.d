module keynavish.grid;

import std.container : SList;
import keynavish;
import keynavish.types;
import keynavish.platform;

struct Grid
{
    Rect rect;
    int rows;
    int columns;
}

private Grid grid_;
private SList!Grid gridStack;

enum GridNavState
{
    row,
    column,
}

bool gridNavEnabled;
GridNavState gridNavState = GridNavState.row;
int gridNavRow = -1;
int gridNavColumn = -1;

void enableGridNav(bool enabled)
{
    gridNavEnabled = enabled;
    gridNavState = GridNavState.row;
    gridNavRow = -1;
    gridNavColumn = -1;
}

void resetGridNavSelection()
{
    gridNavState = GridNavState.row;
    gridNavRow = -1;
    gridNavColumn = -1;
}

const(Grid) grid()
{
    return grid_;
}

void grid(Grid newGrid)
{
    if (newGrid == grid) return;

    gridStack.insertFront(grid);
    grid_ = newGrid;
}

void tryPopGrid()
{
    if (gridStack.empty) return;

    grid_ = gridStack.front;
    gridStack.removeFront();
}

void resetGrid()
{
    import std.algorithm : find;
    import std.range : empty;

    auto cursor = cursorPosition;

    auto cursorScreen = displayRectangles.find!(r => r.contains(cursor));

    // The cursor can sit outside every display rectangle (between mismatched
    // displays, or briefly during an arrangement change), so fall back to the
    // whole virtual screen rather than asserting.
    grid_.rect = cursorScreen.empty ? virtualScreenRectangle : cursorScreen[0];
    grid_.rows = 2;
    grid_.columns = 2;
    gridStack = typeof(gridStack)();
}

const(Rect[]) splitGrid()
{
    import std.algorithm : cartesianProduct, map;
    import std.range : array, iota;
    import std.typecons : tuple;

    auto x = grid.rect.left;
    auto y = grid.rect.top;
    auto width = grid.rect.width / grid.columns;
    auto height = grid.rect.height / grid.rows;

    return cartesianProduct(grid.columns.iota, grid.rows.iota).map!(t => t.rename!("x", "y"))
            .map!(t => Rect(x + t.x * width, y + t.y * height, x + (t.x + 1) * width, y + (t.y + 1) * height))
            .array;
}

/// Label shown on a grid-nav cell, e.g. "AB" for row 0, column 1.
char[2] gridNavLabel(int row, int column)
{
    char[2] label;
    label[0] = cast(char)('A' + row);
    label[1] = cast(char)('A' + column);
    return label;
}

//
// Painting.
//
// The layout logic below is shared between platforms; only the four drawing
// primitives it calls (strokeRectangles, fillRectangle, measureLabel,
// drawLabel) are version-gated, in the platform overlay modules.
// See MACOS-PORT.md §5.2b.
//
// `origin` is the top-left of the surface being painted, in global coordinates:
// the virtual screen on Windows (one window spanning everything), or the
// individual display on macOS (one window per display, §6.4).
//
void paintGrid(Canvas canvas, Point origin)
{
    import std.algorithm : map;
    import std.array : array;

    auto cells = splitGrid;

    auto localCells = cells.map!(c => Rect(c.left - origin.x, c.top - origin.y,
                                           c.right - origin.x, c.bottom - origin.y)).array;

    // Two passes, wide light pen first then the narrow dark one on top, so the
    // grid stays legible over both light and dark content.
    canvas.strokeRectangles(localCells, borderPenColour, borderPenWidth * 2 + mainPenWidth);
    canvas.strokeRectangles(localCells, mainPenColour, mainPenWidth);

    if (!gridNavEnabled) return;

    auto textSize = canvas.measureLabel("AA");

    foreach (column; 0 .. grid.columns)
    {
        foreach (row; 0 .. grid.rows)
        {
            auto cell = localCells[column * grid.rows + row];
            auto centerX = cell.left + cell.width / 2;
            auto centerY = cell.top + cell.height / 2;

            auto label = gridNavLabel(row, column);

            auto labelWidth = textSize.width + 25;
            auto labelHeight = textSize.height + 8;
            auto labelRectangle = Rect(centerX - labelWidth / 2, centerY - labelHeight / 2,
                                       centerX + labelWidth / 2, centerY + labelHeight / 2);

            auto rowSelected = gridNavState == GridNavState.column && gridNavRow == row;

            canvas.fillRectangle(labelRectangle,
                                 rowSelected ? gridNavLabelSelectedColour : gridNavLabelColour);

            canvas.drawLabel(centerX - textSize.width / 2, centerY - textSize.height / 2, label[],
                             rowSelected ? gridNavTextSelectedColour : gridNavTextColour);
        }
    }
}
