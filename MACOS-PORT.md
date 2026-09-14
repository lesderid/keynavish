# Porting keynavish to macOS

Plan for bringing keynavish (currently Windows-only, ~2200 lines of D) to macOS,
keeping keynav configuration-file compatibility.

Status: **phases 0-6 implemented on macOS** (see §10). The Windows build is
refactored but unverified -- no Windows machine was available. §14 records where
implementation diverged from this plan.

---

## 1. Goal and constraints

* Same behaviour as the Windows version: a background utility that draws a grid
  overlay, cuts/moves it with the keyboard, and warps/clicks the mouse.
* Reuse the platform-independent half of the codebase rather than forking it.
* Target modern macOS only. Apple Silicon is a first-class target.

### The hard constraint: file compatibility

**Users run one `keynavrc` across keynav (X11), keynavish on Windows, and
keynavish on macOS.** The config format is frozen. Where a macOS API makes the
"natural Mac way" diverge from what keynav or the Windows build does, **matching
existing behaviour wins**, even at the cost of extra work.

Three places where this rule actively changes the design, all of which would have
gone the other way if this were a Mac-native app written from scratch:

* Key resolution must be **keyboard-layout-aware**, because both X11 keysyms and
  Windows virtual-key codes are. macOS keycodes are not (§6.3).
* A config containing commands macOS doesn't implement yet must still **load and
  run** — unknown or deferred commands degrade quietly rather than erroring. This
  matters immediately, because `record`/`playback` are deferred and both appear in
  the stock keybindings (§6.3).
* `super` maps to Command, `alt` to Option — chosen to keep the stock bindings
  (`ctrl+semicolon start`) working unchanged rather than to feel Mac-idiomatic.

Anything that can't be made to match goes in §11 and gets a compatibility issue.

## 2. Decisions to make up front

These shape everything below. All are now implemented except where §14 says otherwise.

| Question | Decision |
|---|---|
| Repo layout | **One repo, one source tree, both platforms**, using `version()`-gated implementations rather than a runtime interface (§5) |
| Version gating style | **Inline wherever possible.** Separate platform modules only where the two implementations share no logic at all — in practice just the overlay window and the status item (§5) |
| Minimum macOS | **13 (Ventura)**, which buys `SMAppService` for launch-at-login and avoids a hand-written LaunchAgent plist |
| Config format | **Frozen.** Unchanged from keynav |
| Config file locations | **Bundled read-only default in `Contents/Resources`, loaded first; the three `~` paths layered over it** (§6.11 option D) |
| Recordings | **Out of scope for the initial port** (§6.3). `record`/`playback` degrade gracefully on macOS until they land |
| Architectures | **Universal: arm64 + x86_64.** macOS 13 still supports Intel, so this covers every machine that can run the minimum OS |
| Overlay window level | **`CGShieldingWindowLevel()`** — above fullscreen apps, captured displays, menu bar, Dock and system alerts (§6.4) |
| Missing Accessibility permission | **Poll and self-activate** — explain, deep-link, keep running, start working the moment the user grants it (§7.1) |
| Menu bar icon | **SF Symbol**, no bundled asset (§6.9) |
| Windows compiler | **Stays on DMD.** LDC is used for macOS only |
| Signing | Apple Developer account is available → Developer ID + notarization (§8) |
| Objective-C interop | **Hand-written clang shim** — no usable D binding exists (§5.5) |
| Program name | Keep `keynavish`. Drop "on Windows" from the tagline |

No open design questions remain; §13 tracks only what was deliberately deferred.

## 3. What ports, what doesn't

Dispositions below assume the inline-first gating strategy of §5 — "stays put"
means the file keeps its current structure with `version` blocks inside it, not
that it is untouched.

| File | LOC | Disposition |
|---|---:|---|
| `commands.d` | 812 | **Stays put.** Parsing, verification, dispatch and the `cut`/`move`/`cellSelect` arithmetic are all neutral. Only the action bodies get inline gating, mostly around one `postMouseEvent` primitive (§5.2b) |
| `keyboardinput.d` | 450 | **Stays put.** Binding parsing, registration, and the whole body of `lowLevelKeyboardProc` are neutral once refactored into `handleKeyDown` (§5.2b). The `VK_*` name table becomes shared data (§6.3); each platform adds a thin native callback |
| `grid.d` | 223 | **Stays put.** `Grid`, the stack, `splitGrid`, grid-nav state are neutral. `paintGrid` keeps its logic and gates four drawing primitives. Display queries get inline blocks. `primaryDeviceResolution` is deleted — it only existed to normalise `MOUSEEVENTF_ABSOLUTE` (§6.1) |
| `notifyicon.d` | 210 | **Separate modules.** Shell notify icon + registry vs. `NSStatusItem` + `SMAppService`; nothing in common |
| `window.d` | 95 | **Separate modules.** `CreateWindowEx` + `windowProc` vs. one `NSWindow` per screen |
| `recording.d` | 160 | **Untouched, inert on macOS.** Recordings are deferred (§6.3); the file stays compiled and neutral, with `recordingActive` false and `loadRecordings` a no-op, so nothing has to be un-done when it lands |
| `main.d` | 119 | **Mostly rewritten.** `WinMain`/`_d_run_main` and the `GetMessage` loop vs. `NSApplication`; the startup sequence itself is shared |
| `errorhandling.d` | 51 | **Stays put.** Three small functions, inline-gated `MessageBox` vs. `NSAlert` (with a caveat, §6.12) |
| `helpers.d` | 55 | **Stays put.** `expandPath` needs inline gating for `USERPROFILE` and the `/` → `\` rewrite |
| `config.d` | 29 | **Stays put.** Colour constants carry over; `windowColourKey` becomes dead on macOS (§6.5) |
| `package.d` | 13 | Minor |

Genuinely portable with no change at all: `parseCommaDelimitedCommands`,
`verifyCommand`, the grid arithmetic, config file discovery and parsing, and the
recording file format logic.

## 4. Toolchain

* **LDC is required on macOS.** DMD has no native arm64 macOS backend; it only
  targets x86_64 (via Rosetta on Apple Silicon). LDC targets `arm64-apple-macos`
  natively. **The Windows build stays on DMD** (§2); LDC is a macOS-only
  requirement. Worth being aware that this means two codegen backends in play —
  if a bug ever reproduces on only one platform, the compiler is a suspect.
* Verified on this machine: **LDC 1.43.0** (DMD 2.113 frontend, LLVM 23.1),
  default target `arm64-apple-darwin`, with `x86-64` also registered — so
  universal binaries can be produced locally. Xcode 26.5 SDK is present, which
  covers clang for the shim.
* `dub` 1.42.0 is installed alongside it.
* Ship a universal binary: build twice (`-mtriple=arm64-apple-macos13`,
  `-mtriple=x86_64-apple-macos13`) and `lipo -create` the results.
* **Two caveats found during implementation**, both pointing the same way — a
  real release needs the official LDC release rather than the Homebrew package:
  * Homebrew's LDC ships **arm64-only** druntime and phobos, so it physically
    cannot produce the x86_64 slice. `ldc2-*-osx-universal` ships both.
  * Its runtime libraries are themselves built for macOS 26, so linking with
    `-mmacosx-version-min=13.0` emits "built for newer macOS version" warnings
    and the result may not actually run on 13.
* `dub.sdl` gains `platform=` suffixes rather than separate configurations —
  `libs "User32" "Gdi32" platform="windows"`,
  `lflags "-framework" "Cocoa" platform="osx"`, and so on. On macOS the frameworks
  needed are Cocoa, CoreGraphics, ApplicationServices, Carbon and ServiceManagement.
* `preBuildCommands "generate-version-info.bat"` needs a `platform="posix"` `.sh`
  sibling. The `.rc`/`.res` version-resource half is Windows-only; on macOS the
  equivalent metadata goes in `Info.plist` (`CFBundleShortVersionString`).

## 5. Architecture: one binary source, `version()`-gated implementations

No interfaces, no vtables, no runtime dispatch. D's `version()` does all the
platform selection at compile time, which is both the idiomatic choice and the
zero-cost one — a missing or mistyped platform function is a compile error, not a
link-time surprise or a null method pointer.

### 5.1 Neutral geometry types

First, so `grid.d` and the command bodies stop importing `core.sys.windows`:

```d
struct Point { int x, y; }
struct Rect  { int left, top, right, bottom; }   // Y grows down, same as RECT
```

`Rect` deliberately keeps the Windows `RECT` field layout and top-left/Y-down
convention, so the existing arithmetic in `cut`, `move`, `cellSelect` and
`splitGrid` is untouched. All macOS coordinate conversion happens at the edges
(§6.1).

### 5.2 Inline first

The default is an inline `version` block in the existing function, keeping the
shared logic in one place. A separate platform module is the exception, used only
where the two implementations have no logic in common at all.

**(a) Inline blocks** — small divergences inside otherwise-shared functions:

```d
string expandPath(string input)
{
    version (Windows) auto homeDir = environment.get("HOME", environment.get("USERPROFILE"));
    else              auto homeDir = environment.get("HOME", nsHomeDirectory);
    ...
    version (Windows) return result.replace("/", "\\");
    else              return result;
}
```

Covers `expandPath`, the portable-config path in `loadAllConfigs`, `restart`, the
three dialog functions in `errorhandling.d`, and the display queries
(`displayRectangles`, `virtualScreenRectangle`).

**(b) Shared logic, version-gated primitives** — the pattern that does the most
work here. Several subsystems look platform-specific but are 80% shared decision
logic wrapped around a handful of genuinely different calls. Keep the logic
shared and gate only the primitives:

* **`lowLevelKeyboardProc`** — the whole body (modifier assembly, `active`
  handling, grid-nav interception, recording, binding lookup, deciding whether to
  swallow) is platform-neutral. Refactor it into
  `bool handleKeyDown(KeyCode, BitFlags!ModifierKey)` returning "consume", with a
  thin version-gated callback on each side translating the native event in and the
  consume flag out. Most of `keyboardinput.d`'s 450 lines stays shared.
* **`paintGrid`** — cell geometry, label text, colours and the two-pass
  border/main stroke are all shared. Gate four primitives: `strokeRects`,
  `fillRect`, `drawText`, `measureText`.
* **`click` / `doubleClick` / `drag`** — button parsing, the `x-set-delay` split
  and the drag state machine are shared. Gate one `postMouseEvent` primitive.

**(c) Version-gated aliases** for platform types that leak into neutral code:

```d
version (Windows)  alias KeyCode = DWORD;    // VK_*
else version (OSX) alias KeyCode = ushort;   // CGKeyCode
```

Note this alias is for the *in-memory* key identity only. What gets written to the
recordings file is a Windows VK code on **both** platforms, so the file stays
portable (§1, §6.3).

**(d) Separate modules** — only where nothing is shared:

| Module | Why it can't be inlined |
|---|---|
| `platform/windows/overlay.d` / `platform/macos/overlay.d` | `CreateWindowEx` + `windowProc` vs. one `NSWindow` per screen driven by the shim. No common structure |
| `platform/windows/trayicon.d` / `platform/macos/statusitem.d` | `Shell_NotifyIcon` + `TrackPopupMenu` + registry vs. `NSStatusItem` + `NSMenu` + `SMAppService` |
| `platform/macos/shim.{m,d}` | The clang-compiled Objective-C shim and its `extern(C)` declarations (§5.5) |

Each is selected by a two-line re-export:

```d
module keynavish.platform.overlay;

version (Windows)  public import keynavish.platform.windows.overlay;
else version (OSX) public import keynavish.platform.macos.overlay;
else static assert(false, "keynavish supports Windows and macOS only");
```

### 5.3 File-scope gating (a dub mechanic worth getting right)

dub compiles **every** `.d` file under `src/` regardless of target, so
`platform/macos/*.d` would be handed to the Windows compiler and vice versa.
Guard each platform module at file scope, immediately after the module
declaration:

```d
module keynavish.platform.macos.overlay;

version (OSX):

import core.sys.darwin.mach.port;
...
```

Everything after `version (OSX):` — imports included — disappears on other
targets, leaving an empty module. The alternative,
`excludedSourceFiles "src/keynavish/platform/macos/*.d" platform="windows"` in
`dub.sdl`, also works but is easy to forget when adding a file.

### 5.4 Optional: make the contract explicit

The cost of duck-typed modules is that an unimplemented function shows up as an
error at the *call site* rather than at the implementation. One `static assert`
block per platform package fixes the diagnostics cheaply:

```d
private void platformContract()
{
    static assert(is(typeof(displayRects())     == Rect[]));
    static assert(is(typeof(cursorPosition())   == Point));
    static assert(is(typeof(warpCursor(Point.init)) == void));
    static assert(is(typeof(installKeyboardHook()) == bool));
    // ...
}
```

Worth adding once the surface stabilises; not worth writing up front while it is
still churning.

### 5.5 Why a shim, not `extern(Objective-C)` or a library

**There is no off-the-shelf D binding for AppKit.** Checked against the dub
registry (September 2026):

| Package | What it is | Verdict |
|---|---|---|
| `appkit` / `cocoa` | — | **Nothing exists.** `appkit` returns zero results |
| `objc` (v0.0.1, Sep 2023) | Static bindings to the Objective-C *runtime* (`objc_msgSend`, `sel_registerName`) | Runtime only, no frameworks. v0.0.1, effectively unmaintained |
| `objc_meta` (v1.1.0, Mar 2024) | Objective-C interop helpers — `"str".ns`, delegate→block conversion | Runtime only. ~580 total downloads and the registry lists its licence as *Proprietary*, which would need checking against GPL-2.0 before any use |
| `dplug:macos` (v16.5.6, Sep 2026) | Part of the dplug audio-plugin framework; hand-rolled Cocoa/CoreGraphics/ObjC-runtime bindings, actively maintained | **Useful as a reference, not as a dependency.** It is a plugin framework, far too heavy to depend on, and licensing is per-subpackage. But it is proven production D↔Cocoa code — worth reading for `NSWindow`/`NSView` subclassing and CoreGraphics drawing patterns, and selectively vendoring with attribution if the licence permits |

So the realistic options are all hand-rolled:

D's own `extern(Objective-C)` is incomplete: no categories, no properties, no
blocks, no protocol conformance declarations, partial ivar support, and thin
real-world usage. The port needs `NSWindow` subclassing, delegate protocols and a
status-item menu — all awkward or impossible there.

Calling `objc_msgSend` by hand is possible (it's a plain C symbol) but requires
casting to the exact function-pointer signature at every call site, and differs
between arm64 and x86_64 for struct/float returns.

**Instead: a single `macos_shim.m` compiled by clang, exposing a flat C API.**
D only ever calls C. The shim owns:

* `NSApplication` setup and run loop
* Overlay `NSWindow`s and their views
* `NSStatusItem` + menu (it calls back into exported D functions for the actions)
* `NSAlert`
* `SMAppService` registration

Everything else on macOS is already a C API and can be called directly from D:
CoreGraphics (event taps, event synthesis, display enumeration, drawing),
ApplicationServices/AX (focused-window geometry), Carbon HIToolbox
(`UCKeyTranslate`), CoreText (label rendering).

Build wiring: `preBuildCommands` runs clang to produce `macos_shim.o`, and
`sourceFiles` hands it to the linker.

## 6. Subsystem mapping

### 6.1 Coordinate systems — the main correctness trap

Three systems are in play:

1. **Windows virtual screen** — origin at primary monitor top-left, Y down.
2. **Quartz global display space** — origin at main display top-left, Y down.
   Used by `CGDisplayBounds`, `CGEventGetLocation`, `CGWarpMouseCursorPosition`,
   `CGEventCreateMouseEvent`, and the AX position attribute.
3. **AppKit screen space** — origin at primary screen **bottom-left**, Y **up**.
   Used by `NSScreen.frame`, `NSWindow.setFrame:`.

(1) and (2) agree, which is why `Rect` should stay Y-down. Only the shim's
window-placement calls need conversion:

```
appKitY = primaryScreenHeight - (quartzY + height)
```

where `primaryScreenHeight` is the height of `NSScreen.screens[0]` (the screen
owning the origin), re-read whenever the display arrangement changes.

Also: **points vs pixels.** `CGDisplayBounds` and `NSScreen.frame` are in points;
Retina backing scale is handled by AppKit. The grid should be computed entirely in
points. `primaryDeviceResolution` in `grid.d` exists only to normalise
`MOUSEEVENTF_ABSOLUTE` coordinates to 0–65535 — that whole concept disappears,
since Quartz mouse events take absolute point coordinates directly.

### 6.2 Global keyboard capture

`SetWindowsHookEx(WH_KEYBOARD_LL)` → **CGEventTap**:

```c
CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                 kCGEventTapOptionDefault,
                 CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventFlagsChanged),
                 callback, userInfo);
```

then `CFMachPortCreateRunLoopSource` + `CFRunLoopAddSource(CFRunLoopGetMain(), …)`.

Notes:

* Returning `NULL` from the callback **consumes** the event — the exact analogue of
  returning `1` from the Windows hook. Returning the event passes it through, like
  `CallNextHookEx`.
* `CGEventTapCreate` returns `NULL` without Accessibility permission (§7). This
  must be detected and surfaced, not asserted on.
* The system **disables a tap that is too slow**. The callback must handle
  `kCGEventTapDisabledByTimeout` and `kCGEventTapDisabledByUserInput` by calling
  `CGEventTapEnable(port, true)`. This is not optional — it will happen in practice.
* Consequence: never show a modal dialog from inside the callback (§6.12).
* Modifiers come from `CGEventGetFlags`: `kCGEventFlagMaskControl`, `…Shift`,
  `…Alternate` (Option), `…Command`. Map keynav `super` → **Command**, `alt` →
  **Option**. This makes `ctrl+semicolon start` work unchanged.
* The tap runs on the main thread's run loop. If it is later moved to its own
  thread for latency, that thread must call `thread_attachThis()` for the D GC.

### 6.3 Key names to keycodes, and the recordings file

This is where the compatibility constraint (§1) does real work, so the reasoning
matters more than the conclusion.

**The three platforms do not agree on what a "key" is:**

| | What identifies a key | Layout-dependent? |
|---|---|---|
| X11 (keynav) | keysym | **Yes** — the keysym is what the key *produces* under the current layout |
| Windows (keynavish) | virtual-key code | **Yes** — the layout driver maps scancode to VK, so on AZERTY the physical QWERTY-`Q` key delivers `VK_A` |
| macOS | `kVK_*` virtual keycode | **No** — pure hardware position, never remapped by the layout |

macOS is the odd one out. A fixed `"a" -> kVK_ANSI_A` table would make keynavish
behave differently from both keynav and the Windows build on any non-QWERTY
layout: an AZERTY user's `h`/`j`/`k`/`l` bindings would land on different physical
keys than they do on their other machines, from the same config file.

**So macOS needs an explicit translation step that the other two platforms get for
free from the OS.** Two-tier resolution:

* **Character keys** (letters, digits, `semicolon`, `bracketleft`, `at`, `plus`,
  `comma`, `minus`, `period`, …) — build a character-to-keycode map at startup by
  running keycodes `0…127` through `UCKeyTranslate`, with the layout from
  `TISCopyCurrentKeyboardLayoutInputSource` / `kTISPropertyUnicodeKeyLayoutData`,
  both unshifted and shifted. Rebuild on
  `kTISNotifySelectedKeyboardInputSourceChanged`.
* **Non-character keys** — fixed `kVK_*` table: `Escape`, `Tab`, `Return`, `space`,
  arrows, `Home`, `End`, `Prior`/`Page_Up`, `Next`/`Page_Down`, `Delete`,
  `KP_0`–`KP_9`, `Super_L`/`Super_R` (to `kVK_Command`/`kVK_RightCommand`).
  `Insert` has no Mac equivalent — map to `kVK_Help` or reject with a warning.

This is essentially what **XQuartz** does to build an X keymap from the current Mac
layout, so its keycode-to-keysym translation is a directly applicable reference
implementation if the `UCKeyTranslate` details get hairy (dead keys, non-ASCII
layouts).

Side benefit: the `at` hack in `parseKeyCombination` (mapping `@` to VK `'2'`
because Windows has no `@` virtual-key code) is not needed on macOS — `@` resolves
through the layout, so `shift+at playback` works on any layout.

#### Recordings: deferred

**`record` and `playback` are out of scope for the initial macOS port.** The design
below is settled and kept here for when they land; it just isn't phase-1 work.

Two things this implies for the initial build, since the recording paths are
currently woven into the keyboard hook (`waitingForRecordingKey`, `replaying`,
`recordingActive` are all checked in `lowLevelKeyboardProc`):

* Those branches must be **inert, not broken**, on macOS — `recordingActive`
  returns false, `loadRecordings` does nothing. The shared `handleKeyDown` keeps
  its structure so nothing has to be un-done later.
* The **stock keybindings include `q record ~/.keynav_macros` and
  `shift+at playback`** (`keyboardinput.d:15-16`). These must degrade quietly — a
  one-line warning at most, never an error dialog on every keypress, and never a
  refusal to load a config that contains them. A user's shared `keynavrc` has to
  keep working unchanged on macOS, which is the whole point of §1.

#### Keeping the recordings file portable (for when it lands)

`recording.d` writes `<numeric keycode> <commands>`, and the format is frozen. The
numbers are currently Windows VK codes; keynav writes X11 keysyms. So **keynav and
keynavish recordings files are already mutually incompatible today** — that ship
sailed long before this port, and no choice here can un-sail it.

Given that, the achievable goal is keynavish-Windows ↔ keynavish-macOS
portability, and it needs no format change:

> **macOS writes Windows VK code numbers too.** Resolve macOS keycode → key name →
> VK code when writing, and VK code → key name → macOS keycode when reading.

VK codes become keynavish's de-facto cross-platform wire numbering, and one
recordings file works on both keynavish platforms. The cost is one extra table:
the existing Windows name-to-VK map, lifted into neutral code as plain integer
enums. It is pure data — none of it needs the Windows API — so this is a small,
low-risk change. The macOS side needs that map bidirectionally, alongside its own
name-to-keycode map.

`keynavrc` itself needs nothing: it stores key *names*, so it is already portable
across all three programs.

### 6.4 Overlay window

| Windows | macOS |
|---|---|
| `WS_EX_LAYERED` + magenta colour key | Real alpha: `opaque = NO`, `backgroundColor = clearColor` |
| `WS_EX_TRANSPARENT` | `ignoresMouseEvents = YES` |
| `WS_EX_NOACTIVATE` | `NSWindowStyleMaskBorderless`, never key |
| `WS_EX_TOPMOST` | `level = CGShieldingWindowLevel()` |
| `WS_POPUP` | `hasShadow = NO` |

Plus `collectionBehavior = CanJoinAllSpaces | Stationary | FullScreenAuxiliary |
IgnoresCycle`, so the overlay follows the user across Spaces and appears over
full-screen apps.

#### Drawing over fullscreen apps

Worth stating plainly, because the Windows intuition is misleading here: **macOS
has no modern equivalent of DirectX exclusive fullscreen**, so this is a much
smaller problem than on Windows, where game overlays have to hook the present
chain to draw anything at all.

Three kinds of fullscreen exist in practice:

| Kind | How common | Can we draw over it? |
|---|---|---|
| Native fullscreen Space (green button) | Very common | **Yes** — needs `FullScreenAuxiliary` in the collection behaviour, or the overlay simply won't appear in that Space |
| Borderless window sized to the screen, menu bar hidden via `NSApplicationPresentationOptions` | What most Mac games and media apps actually do | **Yes** — it is an ordinary window; any higher window level wins |
| True display capture (`CGDisplayCapture` / `CGCaptureAllDisplays`) | Rare in modern software | **Usually** — `CGShieldingWindowLevel()` is *defined* as the level at which a window remains visible over a captured display |

`CGShieldingWindowLevel()` is the chosen level (§2), so all three cases are
covered. What genuinely can't be beaten is an app that captures the display *and*
draws at or above the shielding level itself — which is a deliberate act by that
app, and rare enough not to design around.

The cost of this choice: the overlay also draws over system alerts, notifications
and password prompts while it is visible. That is harmless (it can't intercept
input — `ignoresMouseEvents` is set, and it never becomes key) but it can look
alarming, so it is worth a line in the README. It also matches what keynav does on
X11 with an override-redirect window, which is the behaviour users coming from
Linux will expect.

**Structural difference: one window per display.** The Windows version uses a
single window spanning the whole virtual screen. On macOS, with "Displays have
separate Spaces" on (the default), a single window spanning displays behaves
badly. Create one borderless window per `NSScreen`, each drawing the portion of
the grid that intersects its own bounds. Rebuild the window set on
`NSApplicationDidChangeScreenParametersNotification`.

This also makes `windowColourKey` and the `static assert`s around it dead code on
macOS.

### 6.5 Drawing

GDI → Core Graphics, all C APIs callable directly from D. The two-pass pen trick
maps cleanly:

| Windows | macOS |
|---|---|
| `PolyPolyline` with `borderPen` then `mainPen` | Build one `CGPath` of all cell rects; `CGContextSetLineWidth` + `CGContextStrokePath` twice |
| `CreatePen(PS_SOLID, …)` | `CGContextSetStrokeColorWithColor` / `SetLineWidth` |
| `Rectangle` + `DC_BRUSH` for label background | `CGContextSetFillColorWithColor` + `CGContextFillRect` |
| `CreateFont("Courier New", FW_BOLD, 18)` | `CTFontCreateWithName(CFSTR("Menlo-Bold"), 18, NULL)` |
| `GetTextExtentPoint32` | `CTLineGetTypographicBounds` |
| `TextOut` | `CTLineDraw` |

Existing colours carry over unchanged: main pen `RGB(30,64,64)`, border white,
grid-nav labels `RGB(0,51,0)` / `RGB(0,77,77)` with `RGB(204,204,204)` /
`RGB(255,255,255)` text.

**Colours must be created in device RGB.** `CGColorCreateGenericRGB` is
colour-managed on its way to the display: `RGB(30,64,64)` rendered as
`(38,81,81)`, which would have made the macOS overlay visibly different from the
Windows one. Use `CGColorCreate` with a `CGColorSpaceCreateDeviceRGB` space so
the components are taken literally. Caught by the render test (§14).

**Trap:** a `CGContext` from an `NSView` has a Y-up coordinate system. If the CTM
is flipped to keep the Y-down grid math, text renders upside-down unless the
**text matrix** is flipped too (`CGContextSetTextMatrix` with a `(1, 0, 0, -1)`
scale). Easiest correct approach: convert rects to view-local Y-up coordinates at
the draw-call boundary and leave the CTM alone.

### 6.6 Mouse synthesis

`SendInput` → `CGEventCreate*` + `CGEventPost(kCGHIDEventTap, …)`.

* **warp** — prefer `CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, pt, 0)` over
  `CGWarpMouseCursorPosition`, which doesn't generate an event and introduces a
  post-warp association delay. If `CGWarpMouseCursorPosition` is used anyway,
  follow it with `CGAssociateMouseAndMouseCursorPosition(true)`.
* **click 1/2/3** — `kCGEventLeftMouseDown/Up`, `kCGEventOtherMouseDown/Up` (with
  `kCGMouseEventButtonNumber = 2`), `kCGEventRightMouseDown/Up`.
* **click 4/5** — `CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, ±1)`.
* **doubleclick** — not just two click pairs. macOS apps read
  `kCGMouseEventClickState`; the second pair must have it set to `2`, or apps see
  two separate clicks.
* **drag** — while a button is held, cursor motion must be posted as
  `kCGEventLeftMouseDragged` (etc.), not `kCGEventMouseMoved`. So `draggingFlag`
  changes meaning from "OR-in this MOUSEEVENTF bit" to "which button is currently
  down", used to pick the event type in `warp`.
* **drag modifiers** — the Windows code synthesises modifier key-down/up events
  around the click. On macOS use `CGEventSetFlags(ev, flags)` on the mouse event
  itself. Simpler and less racy.
* `x-set-delay` semantics carry over unchanged.

### 6.7 `windowzoom` and `cursorzoom`

`cursorzoom` needs only the cursor position — `CGEventGetLocation` on a null event,
or `NSEvent.mouseLocation` converted to Quartz coords. Trivial.

`windowzoom` replaces `GetForegroundWindow` + `GetWindowRect` with the
Accessibility API:

```
AXUIElementCreateSystemWide()
  → kAXFocusedApplicationAttribute
  → kAXFocusedWindowAttribute
  → kAXPositionAttribute, kAXSizeAttribute
```

No extra permission needed — Accessibility is already required for the event tap.

Alternative: `CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, …)`
filtered by `NSWorkspace.frontmostApplication.processIdentifier`. Bounds and owner
PID are available without Screen Recording permission (only window *titles* are
gated), but "frontmost on-screen window" is a heuristic there, whereas AX reports
the actually-focused window. **Use AX.**

### 6.8 Displays

`EnumDisplayMonitors` → **`NSScreen` through the shim**, not
`CGGetActiveDisplayList` as originally planned: that call returns zero active
displays on macOS 26 (`err=0, count=0`) while `NSScreen` correctly reports them.
See §14. `GetSystemMetrics(SM_*VIRTUALSCREEN)` → union of those rects.

Using `NSScreen` for enumeration also removes an ordering hazard, since the
overlay windows are positioned against `NSScreen` too: index *i* means the same
display in both places.

`resetGrid`'s "find the display containing the cursor" logic works unchanged once
`displayRects()` is implemented, since both use Y-down global coordinates.

### 6.9 Menu bar item

`Shell_NotifyIcon` → `NSStatusItem` from
`NSStatusBar.systemStatusBar.statusItemWithLength(NSVariableStatusItemLength)`,
with an `NSMenu`. Menu items map 1:1 to the existing `MenuItem` enum: About, Home
page, Launch on startup (checkbox), Edit config file, Reload configuration,
Restart, Exit.

**Icon: an SF Symbol** (§2) — `NSImage(systemSymbolName:accessibilityDescription:)`,
with `isTemplate = true` so it adapts to light and dark menu bars and to every
scale factor with no bundled asset to maintain. `cursorarrow.rays` or
`squareshape.split.3x3` are the obvious candidates; pick by eye at menu bar size.

This is the closest available analogue to what the Windows build does today —
`LoadIcon(LoadLibrary("main.cpl"), MAKEINTRESOURCE(108))` borrows a stock system
mouse icon rather than shipping one (`notifyicon.d:15`).

The same image, in an attention/disabled variant, doubles as the
"Accessibility not granted yet" indicator (§7.1).

The `TaskbarCreated` re-registration dance has no macOS equivalent and is dropped.

The app runs as `NSApplicationActivationPolicyAccessory` (`LSUIElement = true` in
`Info.plist`) — menu bar item, no Dock icon, no app menu.

### 6.10 Launch at login

Registry `Software\Microsoft\Windows\CurrentVersion\Run` →
`SMAppService.mainApp.register()` / `.unregister()`, with
`SMAppService.mainApp.status` driving the menu checkbox. Requires a signed `.app`
bundle. This is the reason for the macOS 13 minimum (§2).

### 6.11 Paths and config discovery

`expandPath` needs two fixes:

* `environment.get("HOME", environment.get("USERPROFILE"))` → `HOME` only on macOS
  (falling back to `NSHomeDirectory()` if unset).
* `replace("/", "\\")` must not run on macOS. Make it Windows-conditional.

Config search order carries over: `~/.keynavrc`, `~/keynavrc`,
`~/.config/keynav/keynavrc`.

#### The portable config location — decided: option D

On Windows, `loadAllConfigs` reads `<dirName(thisExePath)>/keynavrc` first, so a
`keynavish.exe` and a `keynavrc` sitting together on a USB stick travel as a unit.
Inside a bundle, `thisExePath()` is `…/keynavish.app/Contents/MacOS/keynavish`, so
`dirName` is no longer a place a user would ever look.

| Option | Pros | Cons |
|---|---|---|
| **A. `Contents/Resources/keynavrc`** (inside the bundle) | Travels with the `.app` when copied or moved, which is the real analogue of the Windows behaviour. Survives being dragged to `/Applications`. Natural place for a shipped default config | Invisible to users — needs "Show Package Contents". **Editing it breaks the code signature**, which invalidates the Accessibility grant (§7.2) — a genuinely bad failure mode. Wiped by any reinstall or update |
| **B. Next to the `.app`** (`…/keynavish.app/../keynavrc`) | Visible and editable, no signature impact. Closest to the Windows "portable pair" idea | Two loose items that must be kept together, which Mac users don't expect. Meaningless once the app is in `/Applications` — you'd be reading `/Applications/keynavrc` |
| **C. Drop it on macOS**; use only the three `~` paths | Simplest, and matches what Mac users expect. No signature hazard | Loses portable-install support. A behaviour difference from the Windows build — though an invisible one, since the `~` paths are unchanged |
| **D. A + C**: ship a read-only default in `Contents/Resources`, loaded *first*, with the `~` paths layered over it | Gives a sane out-of-box config; user edits go to `~/.keynavrc` where they belong and survive updates; no signature hazard | Slightly more machinery. "Portable install" still isn't really a thing |

**Decided: D.** It preserves the useful half of the Windows behaviour (a bundled
default config) without the signature-invalidation trap, and keeps the
user-editable paths identical across platforms — which is what actually matters
for the shared-config constraint in §1. Option A's signature problem is not
hypothetical: it would silently cost the user their Accessibility permission the
first time they edited their config.

Concretely, `loadAllConfigs` on macOS loads, in order:

1. `<bundle>/Contents/Resources/keynavrc` — shipped default, read-only, silent if absent
2. `~/.keynavrc`
3. `~/keynavrc`
4. `~/.config/keynav/keynavrc`

which is the existing Windows order with the portable slot repointed. Later files
layer over earlier ones exactly as they do today, so a user who has any `~` config
is unaffected by the bundled default.

This also simplifies `editConfigFile` in the status item menu: it should never
offer to edit the bundled file, only the `~` paths — creating `~/.keynavrc` from
the bundled default if none exists, which is what the existing
"use an example config?" prompt already does via `import("keynavrc")`.

`Edit config file` → `NSWorkspace.openURL:` (or `open`) instead of
`ShellExecute`. `Home page` likewise. The `import("keynavrc")` example-config
mechanism works unchanged (`stringImportPaths "."` stays).

### 6.12 Dialogs and error reporting

`MessageBox` → `NSAlert` via the shim.

Most `showError`/`showWarning` calls originate from config parsing (fine), but
some can fire from inside the event tap callback — `showWarning` on a missing
recording, `showError` on a bad mouse button. A modal `NSAlert` there blocks the
run loop, which trips the tap timeout and gets the tap disabled (§6.2).

This is straightforward to avoid; it just has to be designed in rather than
discovered. Two options, and there's no reason not to do both:

* **Defer.** Push the message onto a queue and drain it with
  `dispatch_async(dispatch_get_main_queue(), …)` so the alert is presented after
  the callback has returned. The alert still appears; it simply doesn't appear
  *during* event handling. This is the direct fix and preserves current behaviour.
* **Don't use a modal alert at all for runtime warnings.** A `UNUserNotification`
  (or an attention state on the status item — a badged icon, or a "Last error…"
  menu entry) is both more Mac-idiomatic and structurally incapable of blocking
  the run loop. Modal alerts stay for the startup/config-parsing path, where
  they're appropriate and where blocking is harmless.

Recommended split: **modal `NSAlert` for config-load and startup errors; deferred
notification for anything raised from the hook path.**

`exceptionHandlerWrapper` stays as a concept but loses `extern(Windows)`; on macOS
it wraps the C callbacks handed to CoreGraphics and the shim.

### 6.13 Lifecycle

`GetMessage`/`DispatchMessage` loop → `[NSApp run]` (which drives the same
`CFRunLoop` the event tap source is attached to). `PostQuitMessage(0)` →
`[NSApp terminate:nil]`.

`restart` — `spawnProcess(Runtime.args)` re-executes the inner binary, which
loses bundle identity. Use `open -n <path to .app>` instead, then terminate.

## 7. Permissions (TCC)

This is genuinely new surface area with no Windows analogue and it will dominate
the first-run experience.

* **Accessibility** — *required*. Without it `CGEventTapCreate` returns `NULL` and
  the AX window query fails. Prompt with
  `AXIsProcessTrustedWithOptions({kAXTrustedCheckOptionPrompt: true})`, and see
  §7.1 for what happens when it isn't granted.
* **Input Monitoring** — some macOS versions additionally surface event-tap clients
  under Input Monitoring. Handle a `NULL` tap gracefully regardless of which switch
  the user missed.
* **Screen Recording** — *not needed*, given AX is used for `windowzoom` (§6.7).

### 7.1 First-run flow: poll and self-activate

Every user's first launch is the un-permitted state, so this is a primary path,
not an error path. Decided behaviour:

1. On startup, call `AXIsProcessTrustedWithOptions` with the prompt option, which
   shows Apple's own "…would like to control this computer" dialog.
2. If not trusted, **keep running**. Put the status item in an attention state, and
   offer a menu entry that deep-links to
   `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
3. Poll `AXIsProcessTrusted()` on a timer (1s is fine; it is a cheap call) and, the
   moment it returns true, install the event tap and drop the attention state.
   **No restart required** — this is the point of choosing this option.
4. If the user later revokes permission, the tap dies. Handle that by watching for
   tap failure and falling back into the polling state rather than wedging.

Implementation note: this means tap installation must be separable from startup —
`installKeyboardHook()` has to be callable later, not only from `static this()` as
the Windows version does today (`main.d:34`). Worth getting right during the phase
1 refactor rather than retrofitting.

### 7.2 What "TCC grants are tied to the code signature" means in practice

macOS does not remember "the user allowed Accessibility for the app at this path".
It records the grant against the app's **bundle identifier plus its designated
requirement** — a rule derived from the code signature describing what a binary
must prove to be considered *the same app*.

The failure mode this produces is specific and confusing:

* With an **ad-hoc signature** (`codesign -s -`, the default for a locally built
  binary), the designated requirement can only be pinned to the `cdhash` — a hash
  of the binary itself. Every rebuild changes the binary, so every rebuild produces
  a different `cdhash`, and macOS concludes this is a *different app wearing the
  same name*.
* The grant is then silently not applied. **The checkbox in System Settings stays
  visibly ticked**, but `AXIsProcessTrusted()` returns false and
  `CGEventTapCreate` returns `NULL`. The app looks authorised and behaves as if it
  isn't.
* Recovering means unticking and re-ticking (often actually removing the entry with
  `−` and re-adding it) — **after every single build**.

* With a **stable signing certificate**, the designated requirement is expressed in
  terms of the bundle identifier and the certificate, not the binary hash. Rebuilds
  keep the grant, because the new build still satisfies the rule. This is the
  entire fix.

Practical consequences:

* **Development:** create a self-signed code-signing certificate once, trust it in
  the login keychain, and sign every local build with it. One-time setup, and it
  removes the re-approval loop completely.
* **Debugging:** `tccutil reset Accessibility <bundle-id>` clears the stored state
  when it gets into a confusing condition. Expect to need it.
* **Release:** Developer ID signing (available, §2) gives the same stability for
  users, so updates don't silently lose permission.
* **Don't change the bundle identifier casually** — it is half the key. Changing it
  after release orphans every existing user's grant.

## 8. Packaging and distribution

A bare Mach-O binary is not sufficient — `NSStatusItem`, TCC attribution,
`SMAppService` and `LSUIElement` all want a bundle.

```
keynavish.app/Contents/
  Info.plist          # CFBundleIdentifier, LSUIElement=true, LSMinimumSystemVersion=13.0
  MacOS/keynavish     # universal binary
  Resources/          # status item template icon, default keynavrc
```

* **Signing** — an Apple Developer account is available (§2), so: Developer ID
  Application certificate, hardened runtime, then notarization and stapling.
  This also keeps Accessibility grants stable across updates (§7.1).
* **Distribution** — `.dmg` or zip of the `.app`; a Homebrew cask is the natural
  follow-up once releases are notarized.
* Notarization needs credentials in CI — an app-specific password or (better) an
  App Store Connect API key, stored as repository secrets and fed to
  `notarytool`.

## 9. Build and CI

* `dub.sdl`: add `platform=` suffixes to the existing Windows directives, and macOS
  ones for the framework `lflags` and the shim `preBuildCommands`/`sourceFiles`.
  Platform modules are gated at file scope instead of via `excludedSourceFiles`
  (§5.3).
* `generate-version-info.sh` for the `versioninfo.d` half; skip the `.rc`/`.res`
  step off Windows. (Worth taking the opportunity to replace the `.bat` — it is
  self-described as "a bit of a mess".)
* A `Makefile` or script to: build arm64, build x86_64, `lipo`, assemble the
  bundle, sign.
* CI: add a `macos-latest` job (Apple Silicon runners) using
  `dlang-community/setup-dlang` with `ldc-latest`. CD: add the notarized `.dmg`
  as a release asset alongside the existing Windows executables.

## 10. Phased plan

Each phase should leave the tree building on both platforms.

Status: phases 0-6 are implemented and building on macOS. Phase 7 is partly
done (CI and README yes; signing and notarization not, since they need
credentials). Ticks mark what is actually in the tree.

| Phase | Work | Size |
|---|---|---|
| **0** ✅ | LDC + dub macOS config, clang shim build wiring, `.app` assembly script, **stable self-signed dev certificate** (§7.2). Deliverable: an accessory app with an empty status item that launches and quits | M |
| **1** ✅ | Platform refactor (§5): `version()`-gate the existing Windows code, extract the neutral types, make `installKeyboardHook` callable after startup (§7.1). No new platform code, no behaviour change. **Verify on Windows before proceeding** | M |
| **2** ✅ | Event tap + first-run permission flow + layout-aware keycode resolution (§6.2–6.3, §7.1). Deliverable: bindings fire, events are correctly swallowed, permission can be granted without a restart. No UI yet | L |
| **3** ✅ | Overlay windows + Core Graphics drawing, one per display (§6.4–6.5). Deliverable: grid and grid-nav labels render correctly, including Retina, multi-display and over a fullscreen app | L |
| **4** ✅ | Mouse synthesis: warp, click, doubleclick, scroll, drag (§6.6) | M |
| **5** ✅ | `windowzoom` via AX, `cursorzoom`, display-arrangement change handling (§6.7–6.8) | S |
| **6** ✅ | Status item menu, launch at login, edit config, about, restart (§6.9–6.11, §6.13) | M |
| **7** ◐ | Universal build + `lipo`, Developer ID signing, notarization, CI, README, first-run permission documentation | M |
| *later* | Recordings: `record`/`playback` with VK-code-compatible output (§6.3) | M |

Phases 2 and 3 are independent and can be worked in either order; 2 first gives a
testable program sooner.

**Acceptance criterion carried through every phase:** the same `keynavrc` that
works on the Windows build works here, including the `record`/`playback` bindings
that macOS doesn't implement yet (§1).

## 11. Expected behaviour differences

To be recorded in the README, and as compatibility issues where they're
user-visible:

* **Secure Event Input.** While an app has secure input enabled (password fields,
  some terminals), event taps receive nothing — keynavish will appear dead.
  Unavoidable; document it.
* **`record` and `playback` do nothing on macOS initially** (§6.3). Configs
  containing them still load and every other binding works; the two recording
  bindings are simply inert. When they land, one `~/.keynav_macros` will work
  across both keynavish platforms — but never with keynav on X11, which writes
  keysyms and was already incompatible before this port.
* **`super` means Command** on macOS, `alt` means Option.
* **`Insert`** has no natural equivalent.
* **Fullscreen is mostly fine** — better than on Windows, in fact. At
  `CGShieldingWindowLevel()` the overlay draws over native fullscreen Spaces,
  borderless-fullscreen games and captured displays alike (§6.4). Only an app that
  captures the display *and* draws at or above the shielding level itself can beat
  it, which is rare and deliberate.
* **The overlay also covers system alerts and password prompts** while visible —
  the cost of the shielding level. Harmless (it never takes input) but worth a
  README line. keynav on X11 behaves the same way.
* **Per-display overlays** rather than one virtual-screen window — visible only if
  something depends on the window's exact geometry.

## 12. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| D↔Objective-C integration is more painful than estimated | High | The shim design (§5.5) keeps the D side pure C calls; prototype it in phase 0 before committing |
| Event tap disabled by timeout under load | High — looks like random unresponsiveness | Handle the disable events explicitly; keep the callback allocation-free and non-blocking; defer all dialogs |
| TCC grant silently invalidated on rebuild — checkbox looks ticked but isn't honoured | Medium — wastes hours if not understood up front | Stable self-signed development certificate; `tccutil reset` (§7.2) |
| Layout-aware keycode mapping is fiddly (`UCKeyTranslate` dead keys, non-ASCII layouts) | Medium | Use XQuartz's keycode→keysym translation as reference (§6.3). Falling back to the positional `kVK_*` table is **not** an acceptable mitigation — it breaks the §1 compatibility constraint. Better to warn on the specific key that can't be resolved |
| Behaviour drifts from keynav/Windows keynavish in ways nobody notices until a user reports it | Medium — erodes the project's core promise | Test with a non-QWERTY layout explicitly; test one shared `keynavrc` and one shared recordings file across both keynavish platforms as an acceptance criterion for phase 2 |
| D GC interacting badly with CoreFoundation callbacks | Low–Medium | Keep callbacks on the main thread; `thread_attachThis()` if that changes |
| Two compiler backends (DMD on Windows, LDC on macOS) mask a codegen-specific bug | Low | Known and accepted (§4); revisit if it ever bites |

## 13. Open questions and deferred work

**None.** Every design question raised while writing this plan is now settled in
§2. What follows is deliberately deferred work, not undecided work.

### Deferred

* **Recordings** — `record`/`playback` are out of the initial port (§6.3, phase
  *later* in §10). The approach is settled: write Windows VK codes on macOS too,
  so one `~/.keynav_macros` works across both keynavish platforms.
* **`Insert` key name** — map to `kVK_Help` or reject with a warning (§6.3).
  A one-line decision, best made with the keycode table in front of you.
* **Homebrew cask** — natural follow-up once notarized releases exist (§8).
* **Standardising both platforms on LDC** — declined for now (§2), but it would
  remove a class of "reproduces on only one platform" ambiguity (§4).

## 14. Implementation notes

Where the code ended up differing from the plan above, and why. Recorded so the
plan stays honest rather than quietly wrong.

### 14.1 Plan changes forced by reality

| Planned | Actual | Why |
|---|---|---|
| Enumerate displays with `CGGetActiveDisplayList` + `CGDisplayBounds` (§6.8) | **`NSScreen`, via the shim** | `CGGetActiveDisplayList` returns `err=0, count=0` on macOS 26 while `NSScreen` correctly reports both displays. The CoreGraphics call is the documented one and needs no permission, but it cannot be relied on. Bonus: the overlay windows are positioned against `NSScreen` anyway, so using it for enumeration too means index *i* is the same display in both places |
| `CGColorCreateGenericRGB` for grid colours (§6.5) | **`CGColorCreate` with a device RGB space** | Generic RGB is colour-managed on its way to the display: `RGB(30,64,64)` came out as `(38,81,81)`. The grid has to match the Windows build exactly, so the components must be taken literally |
| Universal binary built locally (§4) | **arm64 only with the Homebrew toolchain** | Homebrew's LDC ships arm64-only druntime/phobos. `tools/build-macos.sh` detects this and says what is needed rather than emitting a wall of linker errors. CI uses the official LDC, which ships both slices |
| `primaryDeviceResolution` deleted (§3) | **Kept, Windows-only** | Deleting it meant changing how `warp` computes absolute coordinates on Windows, which is untestable here. See §14.3 |

### 14.2 Things worth knowing that the plan didn't anticipate

* **A bundle is required earlier than expected.** `NSStatusBar` kills an
  unbundled process outright — silently, with exit status 0. The `.app`
  assembly script had to exist before anything could be tested at all.
* **Window-server access can't be assumed in a build environment.** Anything
  touching AppKit dies silently when the process has no window-server
  connection; only the *build* is safely headless.
* **`[NSApp run]` never returns.** `terminate:` exits the process, so no cleanup
  after `messageLoop()` runs on macOS. Nothing currently depends on that, but
  `removeNotifyIcon()` in `runKeynavish` is dead code on macOS.
* **CoreGraphics window bounds are not window frames.** `CGWindowListCopyWindowInfo`
  reported the overlay windows as inset by ~19x11pt; the actual `NSWindow.frame`
  was correct. Don't use the former to verify geometry.

### 14.3 Deliberate behaviour changes to Windows

Only one, and it is a robustness fix rather than a feature change:

* **`resetGrid` no longer asserts when the cursor is outside every display
  rectangle**, it falls back to the whole virtual screen. The original did
  `assert(!cursorScreen.empty)` and then indexed the range -- which in a release
  build, where the assert is compiled out, indexes an empty range. The case is
  reachable on macOS (the cursor can sit between mismatched displays, or on the
  exclusive edge, since `contains` uses `< right`/`< bottom`), so a fallback was
  needed there; having the two platforms diverge on it would have been worse.

### 14.4 Known issues, deliberately not fixed

* **Windows `warp` is wrong on multi-monitor setups.** It normalises
  `MOUSEEVENTF_ABSOLUTE` coordinates against the *primary display* resolution
  while the grid works in virtual-screen coordinates, so warping onto a
  secondary monitor lands in the wrong place. This predates the port and is
  preserved verbatim. The fix is `MOUSEEVENTF_VIRTUALDESK` plus normalising
  against `virtualScreenRectangle`, but it is a behaviour change to a platform
  that could not be tested here, so it is left for a separate change.
* **A comma inside a quoted argument still splits the command.**
  `sh "echo hello, world"` parses as two commands. The outer comma split only
  honours quotes at the start of a field. Shared with the Windows build; pinned
  by a test so it can't drift between platforms.

### 14.5 Testing

Three suites under `tests/`, run by `tools/run-tests.sh`. None need
Accessibility permission, so they run unattended and in CI.

| Suite | Checks | Covers |
|---|---:|---|
| `config_test.d` | 31 | Stock keybindings all register, the repository `keynavrc` parses completely (61 binding lines), command verification, `record`/`playback` still load on macOS, path expansion |
| `keys_test.d` | 47 | Key-name resolution against the live layout, keycode round-tripping for grid-nav, distinctness, rejection of unknown names, modifier predicates |
| `render_test.d` | 14 | Renders the grid into an offscreen bitmap: geometry from `splitGrid`, global-to-window translation, exact colour match with the Windows constants, grid-nav label placement and selection highlight |

The render test is what caught the colour-management bug, which would otherwise
have shipped as a subtle visual difference nobody could easily name.

### 14.6 Not verified

* **The Windows build.** Refactored but never compiled or run — no Windows
  machine was available. Windows code was moved with behaviour preserved
  verbatim and the risky parts left alone, but it needs a real build before
  anyone relies on it. This is the single largest gap.
* **The event tap and everything downstream of it** — key handling, mouse
  synthesis, `windowzoom`. All need Accessibility permission, which has to be
  granted interactively. The app correctly detects its absence and enters the
  polling state, which is as far as automated testing can reach.
* **Retina rendering and multi-display overlay placement**, beyond the window
  geometry reported by AppKit. Both need eyes on a screen.
