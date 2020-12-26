module keynavish.notifyicon;

import keynavish;

import core.sys.windows.windows;

@system nothrow:

NOTIFYICONDATA notifyIconData;
HMENU popupMenu;

void addNotifyIcon()
{
    //TODO: Error handling

    createPopUpMenu();

    auto icon = LoadIcon(LoadLibrary("main.cpl"), MAKEINTRESOURCE(108));

    notifyIconData.uVersion = 4;
    notifyIconData.uFlags = NIF_ICON | NIF_TIP | NIS_HIDDEN;
    notifyIconData.hWnd = windowHandle;
    notifyIconData.szTip = programName;
    notifyIconData.hIcon = icon;
    notifyIconData.uCallbackMessage = WM_USER;

    Shell_NotifyIcon(NIM_ADD, &notifyIconData);
    Shell_NotifyIcon(NIM_SETVERSION, &notifyIconData);
}

void removeNotifyIcon()
{
    Shell_NotifyIcon(NIM_DELETE, &notifyIconData);
}

void handleNotifyIconMessage(WPARAM wParam, LPARAM lParam)
{
    if (LOWORD(lParam) == WM_CONTEXTMENU)
    {
        POINT cursorPosition;
        GetCursorPos(&cursorPosition);

        SetForegroundWindow(windowHandle);
        auto command = cast(MenuItem) TrackPopupMenu(popupMenu,
                                                     TPM_LEFTALIGN | TPM_BOTTOMALIGN | TPM_RIGHTBUTTON | TPM_RETURNCMD,
                                                     cursorPosition.x,
                                                     cursorPosition.y,
                                                     0,
                                                     windowHandle,
                                                     null);

        handleCommand(command);
    }
}

void handleCommand(MenuItem menuItem)
{
    final switch (menuItem) with (MenuItem)
    {
        case Help:
            ShellExecute(null, "open", programUrl, null, null, SW_SHOWNORMAL);
            break;
        case ToggleLaunchOnStartup:
            showError("Not implemented yet!");
            break;
        case OpenConfigFile:
            showError("Not implemented yet!");
            break;
        case About:
            showInfo(programInfo);
            break;
        case Exit:
            PostQuitMessage(0);
            break;
        case None:
            break;
    }
}

enum MenuItem
{
    None,
    Help,
    ToggleLaunchOnStartup,
    OpenConfigFile,
    About,
    Exit
}

void createPopUpMenu()
{
    import std.exception : assumeWontThrow;
    import std.format : format;
    import std.conv : to;

    popupMenu = CreatePopupMenu();

    wchar* formatTitle(alias formatString, Args...)(Args args)
    {
        return format!(formatString ~ "\0")(args).to!wstring.assumeWontThrow.dup.ptr;
    }

    void addSeparator()
    {
        InsertMenu(popupMenu, -1, MF_BYPOSITION | MF_SEPARATOR, 0, null);
    }

    void addStringItem(alias formatString, MenuItem menuItem, Args...)(Args args)
    {
        InsertMenu(popupMenu, -1, MF_BYPOSITION | MF_STRING, menuItem, formatTitle!formatString(args));
    }

    void addCheckboxItem(alias formatString, MenuItem menuItem, Args...)(bool checked, Args args)
    {
        InsertMenu(popupMenu, -1, MF_BYPOSITION | (checked ? MF_CHECKED : MF_UNCHECKED), menuItem, formatTitle!formatString(args));
    }

    addStringItem!("Help", MenuItem.Help);
    addSeparator();
    addCheckboxItem!("Launch %s on startup", MenuItem.ToggleLaunchOnStartup)(false, programName);
    addStringItem!("Open config file", MenuItem.OpenConfigFile);
    addSeparator();
    addStringItem!("About %s (%s)...", MenuItem.About)(programName, gitVersion);
    addStringItem!("Exit", MenuItem.Exit);
}