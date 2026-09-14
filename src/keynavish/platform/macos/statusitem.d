module keynavish.platform.macos.statusitem;

version (OSX):

import std.string : toStringz;
import keynavish;
import keynavish.platform.macos.shim;
import keynavish.platform.macos.input;

//
// Menu bar item. Replaces the Windows shell notification icon; the menu
// structure is deliberately identical so the two builds behave the same.
//

enum MenuItem
{
    None,
    Help,
    ToggleLaunchOnStartup,
    EditConfigFile,
    ReloadConfig,
    About,
    Restart,
    Exit,
    GrantPermission,
}

void addNotifyIcon()
{
    knv_set_menu_callback(&menuCallback);
    knv_status_item_create(statusItemSymbolName.toStringz, "keynavish".toStringz);

    rebuildStatusMenu();
}

void removeNotifyIcon()
{
    // The status item goes away with the process; nothing to unregister.
}

void setStatusItemAttention(bool attention)
{
    knv_status_item_set_attention(attention ? 1 : 0);
}

void rebuildStatusMenu()
{
    import std.conv : to;
    import std.format : format;

    knv_menu_clear();

    if (awaitingPermission)
    {
        // Until Accessibility is granted the app cannot see any keys, so say so
        // where the user will actually look. See MACOS-PORT.md §7.1.
        knv_menu_add_item("keynavish needs Accessibility permission".toStringz,
                          MenuItem.None, 0, 0);
        knv_menu_add_item("Open Privacy & Security settings…".toStringz,
                          MenuItem.GrantPermission, 0, 1);
        knv_menu_add_separator();
    }

    knv_menu_add_item(format!"About %s (%s)..."(programName, gitVersion).toStringz,
                      MenuItem.About, 0, 1);
    knv_menu_add_item("Home page".toStringz, MenuItem.Help, 0, 1);
    knv_menu_add_separator();
    knv_menu_add_item(format!"Launch %s on startup"(programName).toStringz,
                      MenuItem.ToggleLaunchOnStartup, launchValueExists ? 1 : 0, 1);
    knv_menu_add_item("Edit config file".toStringz, MenuItem.EditConfigFile, 0, 1);
    knv_menu_add_item("Reload configuration".toStringz, MenuItem.ReloadConfig, 0, 1);
    knv_menu_add_separator();
    knv_menu_add_item(format!"Restart %s"(programName).toStringz, MenuItem.Restart, 0, 1);
    knv_menu_add_item("Exit".toStringz, MenuItem.Exit, 0, 1);
}

private extern (C) void menuCallback(int tag) nothrow
{
    try
    {
        handleCommand(cast(MenuItem) tag);
    }
    catch (Throwable)
    {
    }
}

void handleCommand(MenuItem menuItem)
{
    import std.conv : to;

    final switch (menuItem) with (MenuItem)
    {
        case Help:
            knv_open_url(programUrl.toStringz);
            break;
        case ToggleLaunchOnStartup:
            toggleLaunchValue();
            rebuildStatusMenu();
            break;
        case EditConfigFile:
            editConfigFile();
            break;
        case ReloadConfig:
            loadAllConfigs();
            break;
        case About:
            showInfo(programInfo.to!string);
            break;
        case Restart:
            restart();
            break;
        case Exit:
            quitApplication();
            break;
        case GrantPermission:
            openAccessibilitySettings();
            break;
        case None:
            break;
    }
}

bool launchValueExists()
{
    return knv_login_item_enabled() != 0;
}

void toggleLaunchValue()
{
    if (knv_login_item_set(launchValueExists ? 0 : 1) == 0)
    {
        showWarning("Could not change the launch-at-login setting. " ~
                    "This needs keynavish to be installed as an application bundle.");
    }
}

void editConfigFile()
{
    import std.file : exists, write;
    import std.range : empty;
    import std.algorithm : map, find;
    import std.format : format;

    string path;

    // Only the ~ paths are offered for editing, never the read-only copy inside
    // the bundle: editing that would break the code signature and silently
    // invalidate the Accessibility grant. See MACOS-PORT.md §6.11.
    auto configFileRange = configFilePaths.map!expandPath.find!exists;
    if (configFileRange.empty)
    {
        path = configFilePaths[0].expandPath;

        write(path, import("keynavrc"));
        showInfo(format!"No config file found, one has been created at %s."(path));
    }
    else
    {
        path = configFileRange[0];
    }

    knv_open_file(path.toStringz);
}
