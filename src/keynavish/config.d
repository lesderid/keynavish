module keynavish.config;

import core.sys.windows.windows;

enum windowClassName = "keynavish-grid"w;
enum windowColourKey = RGB(255, 0, 255);

enum penColour = RGB(30, 30, 30);
enum penWidth = 1;

static assert(windowColourKey != penColour, "Colour key and pen colour can't be the same");

enum programName = "keynavish";
enum programInfo = programName ~ q"EOS
 – Control the mouse with the keyboard, on Windows.

Copyright © 2020, Les De Ridder <les@lesderid.net>
Home page: <https://github.com/lesderid/keynavish>
EOS";

enum usageHelpString = "Usage: " ~ programName ~ ".exe [options] [optional-startup-commands]\r\n" ~
"Example: " ~ programName ~ ".exe \"loadconfig ~/myconfigs/keynavrc,loadconfig ~/myconfigs/anotherkeynavrc\"\r\n";