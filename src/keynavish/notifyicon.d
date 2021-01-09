module keynavish.notifyicon;

import keynavish;

import core.sys.windows.windows;

NOTIFYICONDATA notifyIconData;
HMENU popupMenu;
HKEY registryKey;

//TODO: Error handling

void addNotifyIcon()
{
    auto icon = LoadIcon(LoadLibrary("main.cpl"), MAKEINTRESOURCE(108));

    notifyIconData.uVersion = 0;
    notifyIconData.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    notifyIconData.hWnd = windowHandle;
    notifyIconData.szTip = programName;
    notifyIconData.hIcon = icon;
    notifyIconData.uCallbackMessage = WM_USER;

    Shell_NotifyIcon(NIM_ADD, &notifyIconData);

    openRegistryKey();
}

void removeNotifyIcon()
{
    Shell_NotifyIcon(NIM_DELETE, &notifyIconData);
}

void handleNotifyIconMessage(WPARAM wParam, LPARAM lParam)
{
    if (lParam == WM_RBUTTONUP || lParam == WM_LBUTTONUP)
    {
        POINT cursorPosition;
        GetCursorPos(&cursorPosition);

        SetForegroundWindow(windowHandle);
        createPopUpMenu();

        auto alignment = GetSystemMetrics(SM_MENUDROPALIGNMENT) != 0 ? TPM_RIGHTALIGN : TPM_LEFTALIGN;
        auto command = cast(MenuItem) TrackPopupMenu(popupMenu,
                                                     alignment | TPM_BOTTOMALIGN | TPM_RIGHTBUTTON | TPM_RETURNCMD,
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
        case ReloadConfig:
            loadAllConfigs();
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
    ReloadConfig,
    About,
    Restart,
    Exit
}

void createPopUpMenu()
{
    import std.format : format;
    import std.utf : toUTF16z;

    if (popupMenu)
    {
        DestroyMenu(popupMenu);
    }

    popupMenu = CreatePopupMenu();

    void addSeparator()
    {
        InsertMenu(popupMenu, -1, MF_BYPOSITION | MF_SEPARATOR, 0, null);
    }

    void addStringItem(alias formatString, MenuItem menuItem, Args...)(Args args)
    {
        InsertMenu(popupMenu, -1, MF_BYPOSITION | MF_STRING, menuItem, format!formatString(args).toUTF16z);
    }

    void addCheckboxItem(alias formatString, MenuItem menuItem, Args...)(bool checked, Args args)
    {
        InsertMenu(popupMenu, -1, MF_BYPOSITION | (checked ? MF_CHECKED : MF_UNCHECKED), menuItem, format!formatString(args).toUTF16z);
    }

    addStringItem!("About %s (%s)...", MenuItem.About)(programName, gitVersion);
    addStringItem!("Home page", MenuItem.Help);
    addSeparator();
    addCheckboxItem!("Launch %s on startup", MenuItem.ToggleLaunchOnStartup)(launchValueExists, programName);
    addStringItem!("Edit config file", MenuItem.EditConfigFile);
    addStringItem!("Reload configuration", MenuItem.ReloadConfig);
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
    return RegQueryValueExW(registryKey, programName.ptr, null, null, null, null) != ERROR_FILE_NOT_FOUND;
}

void toggleLaunchValue()
{
    import core.runtime : Runtime;
    import std.algorithm : map;
    import std.string : join;
    import std.conv : to;
    import std.utf : toUTF16z;

    if (launchValueExists)
    {
        RegDeleteValue(registryKey, programName.ptr);
    }
    else
    {
        //HACK: We should properly quote the strings when necessary
        auto launchValue = Runtime.args.map!(s => '"' ~ s ~ '"').join(' ');

        RegSetValueEx(registryKey, programName.ptr, 0, REG_SZ, cast(ubyte*) launchValue.toUTF16z, cast(uint) (launchValue.length * wchar.sizeof));
    }
}

void editConfigFile()
{
    import std.file : exists, write;
    import std.range : empty;
    import std.algorithm : map, find;
    import std.utf : toUTF16z;
    import std.format : format;

    string path;

    auto configFileRange = configFilePaths.map!expandPath.find!exists;
    if (configFileRange.empty)
    {
        path = configFilePaths[0].expandPath;

        auto result = MessageBox(null,
                                 format!"No config file found, one will be created at %s. Would you like to use an example config?"(path).toUTF16z,
                                 programName.ptr,
                                 MB_YESNOCANCEL);
        if (result == IDCANCEL)
        {
            return;
        }
        else if (result == IDYES)
        {
            write(path, import("keynavrc"));
        }
        else if (result == IDNO)
        {
            write(path, []);
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

    ShellExecute(null, "open", path.toUTF16z, null, null, SW_SHOWNORMAL);
}