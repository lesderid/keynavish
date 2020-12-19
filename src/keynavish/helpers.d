module keynavish.helpers;

import core.sys.windows.windows;

@system nothrow:

LONG width(RECT rect)
{
    return rect.right - rect.left;
}

LONG height(RECT rect)
{
    return rect.bottom - rect.top;
}