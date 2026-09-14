//
// Key-name resolution tests for the macOS port.
//
// This is the highest-risk area for config compatibility: macOS keycodes are
// positional while X11 keysyms and Windows virtual-key codes follow the
// keyboard layout, so keynavish has to translate explicitly here or the same
// keynavrc behaves differently across machines. See MACOS-PORT.md §6.3.
//
// Needs no Accessibility permission -- UCKeyTranslate is unprivileged.
//
// Build and run: tools/run-keys-test.sh
//
module keys_test;

version (OSX):

import core.stdc.stdio : printf;
import std.string : toStringz;
import keynavish.types;
import keynavish.platform.macos.keys;

private int failures;
private int checks;

private void check(string name, bool condition)
{
    checks++;
    printf("%s %s\n", condition ? "  PASS".ptr : "  FAIL".ptr, name.toStringz);
    if (!condition) failures++;
}

private void checkResolves(string keyName)
{
    auto resolved = resolveKeyName(keyName);
    check("resolves '" ~ keyName ~ "'", !resolved.isNull);
}

private void checkResolvesTo(string keyName, KeyCode expected)
{
    auto resolved = resolveKeyName(keyName);
    check("'" ~ keyName ~ "' resolves to the expected keycode",
          !resolved.isNull && resolved.get() == expected);
}

void main()
{
    printf("macOS key resolution test\n");

    buildLayoutMap();

    printf("\nnon-character keys (fixed positional table)\n");

    checkResolvesTo("Escape", kVK_Escape);
    checkResolvesTo("Return", kVK_Return);
    checkResolvesTo("space", kVK_Space);
    checkResolvesTo("Tab", kVK_Tab);
    checkResolvesTo("Left", kVK_LeftArrow);
    checkResolvesTo("Right", kVK_RightArrow);
    checkResolvesTo("Up", kVK_UpArrow);
    checkResolvesTo("Down", kVK_DownArrow);
    checkResolvesTo("Home", kVK_Home);
    checkResolvesTo("End", kVK_End);
    checkResolvesTo("Super_L", kVK_Command);
    checkResolvesTo("Super_R", kVK_RightCommand);

    // keynav accepts both spellings for the page keys.
    check("Prior and Page_Up agree",
          resolveKeyName("Prior") == resolveKeyName("Page_Up"));
    check("Next and Page_Down agree",
          resolveKeyName("Next") == resolveKeyName("Page_Down"));

    // Delete is forward-delete on both X11 (XK_Delete) and Windows (VK_DELETE),
    // which on macOS is kVK_ForwardDelete, NOT the key labelled Delete.
    checkResolvesTo("Delete", kVK_ForwardDelete);

    printf("\nkeypad\n");

    checkResolves("KP_0");
    checkResolves("KP_5");
    checkResolves("KP_9");
    check("keypad codes are distinct",
          resolveKeyName("KP_0") != resolveKeyName("KP_9"));

    printf("\ncharacter keys (resolved through the active layout)\n");

    int lettersResolved;
    foreach (letter; "abcdefghijklmnopqrstuvwxyz")
    {
        if (!resolveKeyName([letter].idup).isNull) lettersResolved++;
    }
    check("all 26 letters resolve", lettersResolved == 26);

    foreach (digit; "0123456789")
    {
        checkResolves([digit].idup);
    }

    // Every key used by the stock keybindings must resolve, or a default
    // install is broken.
    foreach (name; ["semicolon", "bracketleft", "at", "comma", "period", "minus", "plus"])
    {
        checkResolves(name);
    }

    printf("\nround-tripping\n");

    // Grid-nav matches cells by letter, so keycode -> character has to invert
    // character -> keycode for every letter.
    int roundTripped;
    foreach (letter; "abcdefghijklmnopqrstuvwxyz")
    {
        auto resolved = resolveKeyName([letter].idup);
        if (resolved.isNull) continue;

        if (characterForKeyCode(resolved.get()) == letter) roundTripped++;
    }
    check("all letters round-trip through characterForKeyCode", roundTripped == 26);

    printf("\ndistinctness\n");

    // Distinct key names must not collide, or bindings silently shadow one
    // another.
    import std.algorithm : sort, uniq;
    import std.array : array;

    KeyCode[] letterCodes;
    foreach (letter; "abcdefghijklmnopqrstuvwxyz")
    {
        auto resolved = resolveKeyName([letter].idup);
        if (!resolved.isNull) letterCodes ~= resolved.get();
    }
    check("letter keycodes are all distinct",
          letterCodes.sort.uniq.array.length == letterCodes.length);

    printf("\nrejection\n");

    check("unknown key name is rejected", resolveKeyName("NoSuchKey").isNull);
    check("empty key name is rejected", resolveKeyName("").isNull);

    printf("\nmodifier predicates\n");

    check("Command is a modifier", isModifierKey(kVK_Command));
    check("Shift is a modifier", isModifierKey(kVK_Shift));
    check("Control is a modifier", isModifierKey(kVK_Control));
    check("Option is a modifier", isModifierKey(kVK_Option));
    check("a letter is not a modifier", !isModifierKey(resolveKeyName("a").get()));
    check("Escape is recognised", isEscapeKey(kVK_Escape));

    printf("\n%d checks, %d failures\n", checks, failures);
    printf("%s\n", failures == 0 ? "all checks passed".ptr : "FAILURES PRESENT".ptr);

    import core.stdc.stdlib : exit;
    exit(failures == 0 ? 0 : 1);
}
