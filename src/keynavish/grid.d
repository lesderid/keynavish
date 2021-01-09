module keynavish.grid;

import core.sys.windows.windows : RECT, HDC, HPEN;
import std.container : SList;
import keynavish;

struct Grid
{
    RECT rect;
    int rows;
    int columns;
}

private Grid grid_;
private SList!Grid gridStack;

HPEN pen;

int screenWidth;
int screenHeight;

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
    grid_.rect = RECT(0, 0, screenWidth, screenHeight);
    grid_.rows = 2;
    grid_.columns = 2;
    gridStack = typeof(gridStack)();
}

private const(RECT[]) splitGrid()
{
    import std.algorithm : cartesianProduct, map;
    import std.range : array, iota;

    auto x = grid.rect.left;
    auto y = grid.rect.top;
    auto width = grid.rect.width / grid.columns;
    auto height = grid.rect.height / grid.rows;

    return cartesianProduct(grid.columns.iota, grid.rows.iota).map!(t => t.rename!("x", "y"))
            .map!(t => RECT(x + t.x * width, y + t.y * height, x + (t.x + 1) * width, y + (t.y + 1) * height))
            .array;
}

void paintGrid(HDC deviceContext)
{
    import core.sys.windows.windows : DWORD, POINT, PolyPolyline, SelectObject;
    import std.algorithm : map;
    import std.range : repeat, join, array;

    SelectObject(deviceContext, pen);

    auto pointArrays = splitGrid.map!(r => [
        POINT(r.left, r.top),
        POINT(r.right, r.top),
        POINT(r.right, r.bottom),
        POINT(r.left, r.bottom),
        POINT(r.left, r.top)
    ]).join;

    DWORD[] sizes = uint(5).repeat(pointArrays.length).array;
    PolyPolyline(deviceContext, pointArrays.ptr, sizes.ptr, grid.columns * grid.rows);
}