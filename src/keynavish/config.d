module keynavish.config;

import core.sys.windows.windows;

enum windowClassName = "keynavish-grid"w;
enum windowColourKey = RGB(255, 0, 255);

enum mainPenColour = RGB(30, 64, 64);
enum mainPenWidth = 1;
enum borderPenColour = RGB(255, 255, 255);
enum borderPenWidth = 1;

static assert(windowColourKey != mainPenColour, "Colour key and main pen colour can't be the same");
static assert(windowColourKey != borderPenColour, "Colour key and border pen colour can't be the same");

enum programName = "keynavish"w;
enum programInfo = programName ~ q"EOS
 – Control the mouse with the keyboard, on Windows.

Copyright © 2021, Les De Ridder <les@lesderid.net>
EOS" ~ "Home page: <" ~ programUrl ~ ">";
enum programUrl = "https://github.com/lesderid/keynavish";

enum usageHelpString = "Usage: " ~ programName ~ ".exe [options] [optional-startup-commands]\r\n" ~
"Example: " ~ programName ~ ".exe \"loadconfig ~/myconfigs/keynavrc,loadconfig ~/myconfigs/anotherkeynavrc\"\r\n";

enum configFilePaths = ["keynavrc", "~/.keynavrc", "~/keynavrc", "~/.config/keynav/keynavrc"];

enum unhandledExceptionMessage = "This is a bug, please press Ctrl+C and report it at https://github.com/lesderid/keynavish/issues/new.";
