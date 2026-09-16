//
// Config and key-binding tests.
//
// The governing constraint for the macOS port is that one keynavrc works
// unchanged across keynav, keynavish on Windows and keynavish on macOS
// (MACOS-PORT.md §1). These tests check that directly: the stock keybindings
// all register, the repository's own keynavrc parses completely, and the
// commands that macOS does not implement yet still load instead of erroring.
//
// Build and run: tools/run-tests.sh config
//
module config_test;

import core.stdc.stdio : printf;
import std.string : toStringz;
import keynavish;

private int failures;
private int checks;

private void check(string name, bool condition)
{
    checks++;
    printf("%s %s\n", condition ? "  PASS".ptr : "  FAIL".ptr, name.toStringz);
    if (!condition) failures++;
}

private bool hasBindingFor(string bindingString)
{
    import std.algorithm : findSplit, canFind, find;
    import std.range : empty;
    import std.string : split;

    auto parts = bindingString.findSplit(" ");
    auto combination = parts[0].split('+').parseKeyCombination();

    if (combination.isNull) return false;

    return !regularKeyBindings.find!(b => b.keyCombination == combination.get()).empty
        || !startKeyBindings.find!(b => b.keyCombination == combination.get()).empty;
}

void main()
{
    printf("config and key-binding test\n");

    printf("\nstock keybindings\n");

    // Registered by the module constructor in keyboardinput.d.
    check("regular bindings registered", regularKeyBindings.length > 0);
    check("start bindings registered", startKeyBindings.length > 0);

    // Spot-check the bindings a user would notice immediately.
    check("ctrl+semicolon (start) is bound", hasBindingFor("ctrl+semicolon start"));
    check("Escape (end) is bound", hasBindingFor("Escape end"));
    check("h/j/k/l cut keys are bound",
          hasBindingFor("h cut-left") && hasBindingFor("j cut-down")
          && hasBindingFor("k cut-up") && hasBindingFor("l cut-right"));
    check("shift+h move key is bound", hasBindingFor("shift+h move-left"));
    check("space (warp,click,end) is bound", hasBindingFor("space warp"));
    check("digits 1-3 (click) are bound",
          hasBindingFor("1 click 1") && hasBindingFor("2 click 2") && hasBindingFor("3 click 3"));

    // These two are the compatibility trap: record/playback are deferred on
    // macOS, but they are in the stock keybindings, so they must still parse
    // and register rather than raising an error on a shared config.
    check("q (record) still registers", hasBindingFor("q record ~/.keynav_macros"));
    check("shift+at (playback) still registers", hasBindingFor("shift+at playback"));

    printf("\ncommand verification\n");

    check("valid command verifies", verifyCommand(["warp"]));
    check("valid command with arg verifies", verifyCommand(["click", "1"]));
    check("valid two-arg command verifies", verifyCommand(["cursorzoom", "300", "300"]));
    check("unknown command is rejected", !verifyCommand(["nonsense"]));
    check("too many args is rejected", !verifyCommand(["warp", "extra"]));
    check("too few args is rejected", !verifyCommand(["click"]));

    // Commands deferred on macOS must still verify, or configs using them break.
    check("record verifies", verifyCommand(["record"]));
    check("record with path verifies", verifyCommand(["record", "~/.keynav_macros"]));
    check("playback verifies", verifyCommand(["playback"]));

    printf("\ncomma-delimited command parsing\n");

    auto parsed = "warp,click 1,end".parseCommaDelimitedCommands();
    check("three commands parsed", parsed.length == 3);
    check("first is warp", parsed.length > 0 && parsed[0] == ["warp"]);
    check("second is click 1", parsed.length > 1 && parsed[1] == ["click", "1"]);
    check("third is end", parsed.length > 2 && parsed[2] == ["end"]);

    auto quoted = `sh "echo hello world"`.parseCommaDelimitedCommands();
    check("quoted argument is kept as one arg",
          quoted.length == 1 && quoted[0].length == 2 && quoted[0][1] == "echo hello world");

    auto quotedThenCommand = `sh "a b",end`.parseCommaDelimitedCommands();
    check("quoted arg followed by another command",
          quotedThenCommand.length == 2 && quotedThenCommand[0] == ["sh", "a b"]
          && quotedThenCommand[1] == ["end"]);

    // Known limitation, shared with the Windows build and predating this port:
    // the outer comma split only honours quotes at the start of a field, so a
    // comma INSIDE a quoted argument still splits it. Asserted here so the
    // behaviour is at least pinned rather than drifting between platforms.
    auto commaInQuotes = `sh "echo hello, world"`.parseCommaDelimitedCommands();
    check("comma inside quotes splits (known quirk, matches Windows)",
          commaInQuotes.length == 2);

    printf("\nrepository keynavrc\n");

    // Every non-empty, non-comment line of the shipped example config must
    // register. This is the file users are told to start from.
    import std.array : replace, split;
    import std.string : strip, startsWith;

    auto exampleConfig = import("keynavrc");

    int lines;
    int registered;
    foreach (line; exampleConfig.replace("\r", "").split('\n'))
    {
        auto trimmed = line.strip;
        if (trimmed.length == 0 || trimmed.startsWith("#")) continue;

        lines++;
        if (registerKeyBinding(line)) registered++;
    }

    printf("    %d binding lines in keynavrc\n", lines);
    check("keynavrc has content", lines > 0);
    check("every keynavrc line registers", registered == lines);

    version (OSX)
    {
        printf("\nsecure input guidance\n");

        // The instruction has to name the app's own menu, since that is the only
        // place the setting lives -- keynavish and System Settings both have
        // nothing to offer here.
        import keynavish.platform.macos.input : secureInputInstruction;

        check("Terminal gets its own menu path",
              secureInputInstruction("com.apple.Terminal", "Terminal")
              == "Turn off Terminal ▸ Secure Keyboard Entry");
        check("iTerm2 gets its own menu path",
              secureInputInstruction("com.googlecode.iterm2", "iTerm2")
              == "Turn off iTerm2 ▸ Secure Keyboard Entry");
        check("an unknown app still gets named advice",
              secureInputInstruction("com.example.editor", "Some Editor")
              == "Turn off secure keyboard entry in Some Editor");
        check("an unidentifiable app yields no false instruction",
              secureInputInstruction("com.example.editor", "") is null);
        check("no bundle id and no name yields nothing",
              secureInputInstruction("", "") is null);
    }

    printf("\npath expansion\n");

    auto expanded = "~/.keynavrc".expandPath;
    check("tilde is expanded", expanded.length > "~/.keynavrc".length);

    version (Windows)
    {
        import std.algorithm : canFind;
        check("separators are backslashes on Windows", !expanded.canFind('/'));
    }
    else
    {
        import std.algorithm : canFind;
        check("separators stay forward slashes on macOS", !expanded.canFind('\\'));
        check("expands to an absolute path", expanded.length > 0 && expanded[0] == '/');
    }

    printf("\n%d checks, %d failures\n", checks, failures);
    printf("%s\n", failures == 0 ? "all checks passed".ptr : "FAILURES PRESENT".ptr);

    import core.stdc.stdlib : exit;
    exit(failures == 0 ? 0 : 1);
}
