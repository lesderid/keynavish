module keynavish.grid;

import core.sys.windows.windows : RECT, HDC, HPEN;
import std.container : SList;
import keynavish;

@system nothrow:

private RECT gridRect_;
private SList!RECT gridRectStack;

HPEN pen;

int screenWidth;
int screenHeight;

const(RECT) gridRect()
{
    return gridRect_;
}

void gridRect(RECT newRect)
{
    if (newRect == gridRect) return;

    gridRectStack.insertFront(gridRect);
    gridRect_ = newRect;
}

void tryPopGridRect()
{
    if (gridRectStack.empty) return;
    gridRect_ = gridRectStack.front;
    gridRectStack.removeFront();
}

void resetGrid()
{
    gridRect_ = RECT(0, 0, screenWidth, screenHeight);
    gridRectStack = typeof(gridRectStack)();
}

void paintGrid(HDC deviceContext)
{
    import core.sys.windows.windows : DWORD, POINT, PolyPolyline, SelectObject;

    SelectObject(deviceContext, pen);

    auto x = gridRect.left;
    auto y = gridRect.top;
    auto w = gridRect.width / 2;
    auto h = gridRect.height / 2;

    //clockwise
    POINT[] points = [
        {x, y}, {x + w, y}, {x + w, y + h}, {x, y + h}, {x, y},
        {x + w, y}, {x + 2 * w, y}, {x + 2 * w, y + h}, {x + w, y + h}, {x + w, y},
        {x + w, y + h}, {x + 2 * w, y + h}, {x + 2 * w, y + 2 * h}, {x + w, y + 2 * h}, {x + w, y + h},
        {x, y + h}, {x + w, y + h}, {x + w, y + 2 * h}, {x, y + 2 * h}, {x, y + h},
    ];
    DWORD[] sizes = [5, 5, 5, 5];
    PolyPolyline(deviceContext, points.ptr, sizes.ptr, 4);
}