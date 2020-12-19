module keynavish.config;

import core.sys.windows.windows;

enum windowClassName = "keynavish-grid"w;
enum windowColourKey = RGB(255, 0, 255);

enum penColour = RGB(30, 30, 30);
enum penWidth = 1;

static assert(windowColourKey != penColour, "Colour key and pen colour can't be the same");