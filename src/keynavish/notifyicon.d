module keynavish.notifyicon;

import keynavish;

import core.sys.windows.windows;

@system nothrow:

NOTIFYICONDATA notifyIconData;
HMENU popupMenu;
HKEY registryKey;

pragma(lib, "Urlmon");
extern(C) HRESULT URLDownloadToFileW(LPUNKNOWN, LPCTSTR, LPCTSTR, DWORD, void*);

//TODO: Error handling

void addNotifyIcon()
{
    auto icon = LoadIcon(LoadLibrary("main.cpl"), MAKEINTRESOURCE(108));

    notifyIconData.uVersion = 4;
    notifyIconData.uFlags = NIF_ICON | NIF_TIP | NIS_HIDDEN;
    notifyIconData.hWnd = windowHandle;
    notifyIconData.szTip = programName;
    notifyIconData.hIcon = icon;
    notifyIconData.uCallbackMessage = WM_USER;

    Shell_NotifyIcon(NIM_ADD, &notifyIconData);
    Shell_NotifyIcon(NIM_SETVERSION, &notifyIconData);

    openRegistryKey();
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
        createPopUpMenu();
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
            toggleLaunchValue();
            break;
        case EditConfigFile:
            editConfigFile();
            break;
        case About:
            showInfo(programInfo);
            break;
        case Restart:
            restart();
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
    EditConfigFile,
    About,
    Restart,
    Exit
}

void createPopUpMenu()
{
    import std.exception : assumeWontThrow;
    import std.format : format;
    import std.conv : to;

    if (popupMenu)
    {
        DestroyMenu(popupMenu);
    }

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

    addStringItem!("About %s (%s)...", MenuItem.About)(programName, gitVersion);
    addStringItem!("Home page", MenuItem.Help);
    addSeparator();
    addCheckboxItem!("Launch %s on startup", MenuItem.ToggleLaunchOnStartup)(launchValueExists, programName);
    addStringItem!("Edit config file", MenuItem.EditConfigFile);
    addSeparator();
    addStringItem!("Restart %s", MenuItem.Restart)(programName);
    addStringItem!("Exit", MenuItem.Exit);
}

void openRegistryKey()
{
    auto result = RegOpenKeyEx(HKEY_CURRENT_USER, "Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_READ | KEY_SET_VALUE, &registryKey);
    assert(result == ERROR_SUCCESS);
}

bool launchValueExists()
{
    return RegQueryValueExW(registryKey, programName, null, null, null, null) != ERROR_FILE_NOT_FOUND;
}

void toggleLaunchValue()
{
    import core.runtime : Runtime;
    import std.algorithm : map;
    import std.string : join;
    import std.conv : to;
    import std.exception : assumeWontThrow;

    if (launchValueExists)
    {
        RegDeleteValue(registryKey, programName);
    }
    else
    {
        //HACK: We should properly quote the strings when necessary
        auto launchValue = Runtime.args.map!(s => '"' ~ s ~ '"').join(' ').to!wstring.dup.assumeWontThrow;

        RegSetValueEx(registryKey, programName, 0, REG_SZ, cast(ubyte*) launchValue.ptr, cast(uint) (launchValue.length * wchar.sizeof));
    }
}

void editConfigFile()
{
    import std.file : exists, write;
    import std.range : empty;
    import std.algorithm : map, find;
    import std.conv : to;
    import std.exception : assumeWontThrow;
    import std.format : format;

    string path;

    auto configFileRange = configFilePaths.map!expandPath.find!exists;
    if (configFileRange.empty)
    {
        path = configFilePaths[0].expandPath;

        auto result = MessageBox(null,
                                 format!"No config file found, one will be created at %s. Would you like to download an example config?"(path).to!wstring.ptr.assumeWontThrow,
                                 programName,
                                 MB_YESNOCANCEL);
        if (result == IDCANCEL)
        {
            return;
        }
        else if (result == IDYES)
        {
            URLDownloadToFileW(null, exampleConfigUrl, (path ~ "\0").to!wstring.ptr, 0, null).assumeWontThrow;
        }
        else if (result == IDNO)
        {
            write(path, []).assumeWontThrow;
        }
        else
        {
            assert(false);
        }
    }
    else
    {
        path = configFileRange[0];
    }

    ShellExecute(null, "open", (path ~ "\0").to!wstring.ptr.assumeWontThrow, null, null, SW_SHOWNORMAL);
}