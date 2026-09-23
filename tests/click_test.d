//
// Click-counting tests for the macOS mouse path.
//
// The window server counts clicks for a real mouse but not for synthesised
// ones, so keynavish has to fill in kCGMouseEventClickState itself or a second
// `click 1` is seen as an unrelated single click and text never selects.
//
// The rules are pure arithmetic over a button, a position and a timestamp, so
// they can be pinned down here without posting a single event or waiting out a
// real double-click interval.
//
// Build and run: tools/run-tests.sh click
//
module click_test;

version (OSX):

import core.stdc.stdio : printf;
import core.time : Duration, MonoTime, dur;
import std.string : toStringz;
import keynavish.types;
import keynavish.platform.macos.input;

private int failures;
private int checks;

private void check(string name, bool condition)
{
    checks++;
    printf("%s %s\n", condition ? "  PASS".ptr : "  FAIL".ptr, name.toStringz);
    if (!condition) failures++;
}

private enum interval = dur!"msecs"(500);

void main()
{
    printf("macOS click counting test\n");

    auto origin = MonoTime.currTime;
    auto spot = Point(400, 300);

    printf("\na run of clicks in the same place\n");

    ClickCount last;

    check("the first click is a single click",
          advanceClickCount(last, 1, spot, origin, interval) == 1);
    check("a second click soon after is a double click",
          advanceClickCount(last, 1, spot, origin + dur!"msecs"(100), interval) == 2);
    check("a third continues to a triple click",
          advanceClickCount(last, 1, spot, origin + dur!"msecs"(200), interval) == 3);

    printf("\nwhat breaks a run\n");

    // Exactly on the interval still counts; past it does not.
    last = ClickCount.init;
    advanceClickCount(last, 1, spot, origin, interval);
    check("a click exactly on the interval still counts",
          advanceClickCount(last, 1, spot, origin + interval, interval) == 2);

    last = ClickCount.init;
    advanceClickCount(last, 1, spot, origin, interval);
    check("a click past the interval starts over",
          advanceClickCount(last, 1, spot, origin + interval + dur!"msecs"(1), interval) == 1);

    last = ClickCount.init;
    advanceClickCount(last, 1, spot, origin, interval);
    check("a different button starts over",
          advanceClickCount(last, 3, spot, origin + dur!"msecs"(50), interval) == 1);

    last = ClickCount.init;
    advanceClickCount(last, 1, spot, origin, interval);
    check("a click somewhere else starts over",
          advanceClickCount(last, 1, Point(spot.x + 40, spot.y), origin + dur!"msecs"(50), interval) == 1);

    printf("\nsmall movement is tolerated\n");

    // A warp records its target, while the click after it reads the position
    // back from the window server, so the two can disagree by a rounding step.
    // That must not cost the user their double click.
    foreach (offset; [-1, 0, 1])
    {
        last = ClickCount.init;
        advanceClickCount(last, 1, spot, origin, interval);

        auto nudged = Point(spot.x + offset, spot.y + offset);
        check("a click within rounding distance still counts",
              advanceClickCount(last, 1, nudged, origin + dur!"msecs"(50), interval) == 2);
    }

    printf("\nthe count carries across a pause under the limit\n");

    // Each press of `1` is its own command sequence, so the run has to survive
    // the gap between two keystrokes rather than only within one sequence.
    last = ClickCount.init;
    auto at = origin;
    int state;
    foreach (i; 0 .. 4)
    {
        state = advanceClickCount(last, 1, spot, at, interval);
        at += dur!"msecs"(300);
    }
    check("four unhurried keystrokes count up rather than resetting", state == 4);

    printf("\n%d checks, %d failures\n", checks, failures);
    printf("%s\n", failures == 0 ? "all checks passed".ptr : "FAILURES PRESENT".ptr);

    import core.stdc.stdlib : exit;
    exit(failures == 0 ? 0 : 1);
}
