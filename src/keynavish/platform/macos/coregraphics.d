module keynavish.platform.macos.coregraphics;

version (OSX):

//
// Direct bindings to the CoreGraphics / CoreFoundation / ApplicationServices C
// APIs. These need no Objective-C, so they are bound here rather than going
// through the shim. See MACOS-PORT.md §5.5.
//

extern (C):
nothrow:

// --- CoreFoundation --------------------------------------------------------

alias CFTypeRef = void*;
alias CFStringRef = void*;
alias CFDictionaryRef = void*;
alias CFAllocatorRef = void*;
alias CFRunLoopRef = void*;
alias CFRunLoopSourceRef = void*;
alias CFMachPortRef = void*;
alias CFIndex = long;

void CFRelease(CFTypeRef cf);
CFTypeRef CFRetain(CFTypeRef cf);

CFRunLoopRef CFRunLoopGetMain();
CFRunLoopRef CFRunLoopGetCurrent();
void CFRunLoopAddSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFStringRef mode);
CFRunLoopSourceRef CFMachPortCreateRunLoopSource(CFAllocatorRef allocator, CFMachPortRef port, CFIndex order);

extern __gshared CFStringRef kCFRunLoopCommonModes;
extern __gshared CFStringRef kCFRunLoopDefaultMode;

CFStringRef CFStringCreateWithCString(CFAllocatorRef alloc, const(char)* cStr, uint encoding);
enum kCFStringEncodingUTF8 = 0x08000100;

// --- Geometry --------------------------------------------------------------

alias CGFloat = double;

struct CGPoint
{
    CGFloat x;
    CGFloat y;
}

struct CGSize
{
    CGFloat width;
    CGFloat height;
}

struct CGRect
{
    CGPoint origin;
    CGSize size;
}

// --- Displays --------------------------------------------------------------

alias CGDirectDisplayID = uint;
alias CGError = int;

enum kCGErrorSuccess = 0;

CGError CGGetActiveDisplayList(uint maxDisplays, CGDirectDisplayID* activeDisplays, uint* displayCount);
CGRect CGDisplayBounds(CGDirectDisplayID display);
CGDirectDisplayID CGMainDisplayID();

// --- Events ----------------------------------------------------------------

alias CGEventRef = void*;
alias CGEventSourceRef = void*;
alias CGEventTapProxy = void*;
alias CGEventType = uint;
alias CGEventField = uint;
alias CGEventMask = ulong;
alias CGEventFlags = ulong;
alias CGKeyCode = ushort;

enum : CGEventType
{
    kCGEventNull              = 0,
    kCGEventLeftMouseDown     = 1,
    kCGEventLeftMouseUp       = 2,
    kCGEventRightMouseDown    = 3,
    kCGEventRightMouseUp      = 4,
    kCGEventMouseMoved        = 5,
    kCGEventLeftMouseDragged  = 6,
    kCGEventRightMouseDragged = 7,
    kCGEventKeyDown           = 10,
    kCGEventKeyUp             = 11,
    kCGEventFlagsChanged      = 12,
    kCGEventScrollWheel       = 22,
    kCGEventOtherMouseDown    = 25,
    kCGEventOtherMouseUp      = 26,
    kCGEventOtherMouseDragged = 27,
    kCGEventTapDisabledByTimeout   = 0xFFFFFFFE,
    kCGEventTapDisabledByUserInput = 0xFFFFFFFF,
}

enum : CGEventFlags
{
    kCGEventFlagMaskShift     = 0x00020000,
    kCGEventFlagMaskControl   = 0x00040000,
    kCGEventFlagMaskAlternate = 0x00080000,
    kCGEventFlagMaskCommand   = 0x00100000,
}

enum : CGEventField
{
    kCGKeyboardEventKeycode   = 9,
    kCGMouseEventButtonNumber = 3,
    kCGMouseEventClickState   = 1,
    kCGScrollWheelEventDeltaAxis1 = 11,
}

alias CGMouseButton = uint;
enum : CGMouseButton
{
    kCGMouseButtonLeft   = 0,
    kCGMouseButtonRight  = 1,
    kCGMouseButtonCenter = 2,
}

alias CGEventTapLocation = uint;
enum : CGEventTapLocation
{
    kCGHIDEventTap     = 0,
    kCGSessionEventTap = 1,
    kCGAnnotatedSessionEventTap = 2,
}

alias CGEventTapPlacement = uint;
enum : CGEventTapPlacement
{
    kCGHeadInsertEventTap = 0,
    kCGTailAppendEventTap = 1,
}

alias CGEventTapOptions = uint;
enum : CGEventTapOptions
{
    kCGEventTapOptionDefault  = 0,
    kCGEventTapOptionListenOnly = 1,
}

alias CGEventTapCallBack = extern (C) CGEventRef function(CGEventTapProxy proxy,
                                                          CGEventType type,
                                                          CGEventRef event,
                                                          void* userInfo) nothrow;

CFMachPortRef CGEventTapCreate(CGEventTapLocation tap,
                               CGEventTapPlacement place,
                               CGEventTapOptions options,
                               CGEventMask eventsOfInterest,
                               CGEventTapCallBack callback,
                               void* userInfo);
void CGEventTapEnable(CFMachPortRef tap, bool enable);
bool CGEventTapIsEnabled(CFMachPortRef tap);

CGEventRef CGEventCreate(CGEventSourceRef source);
CGPoint CGEventGetLocation(CGEventRef event);
CGEventFlags CGEventGetFlags(CGEventRef event);
void CGEventSetFlags(CGEventRef event, CGEventFlags flags);
long CGEventGetIntegerValueField(CGEventRef event, CGEventField field);
void CGEventSetIntegerValueField(CGEventRef event, CGEventField field, long value);
void CGEventPost(CGEventTapLocation tap, CGEventRef event);

CGEventRef CGEventCreateMouseEvent(CGEventSourceRef source, CGEventType mouseType,
                                   CGPoint mouseCursorPosition, CGMouseButton mouseButton);

alias CGScrollEventUnit = uint;
enum : CGScrollEventUnit
{
    kCGScrollEventUnitPixel = 0,
    kCGScrollEventUnitLine  = 1,
}

CGEventRef CGEventCreateScrollWheelEvent(CGEventSourceRef source, CGScrollEventUnit units,
                                         uint wheelCount, int wheel1, ...);

CGError CGWarpMouseCursorPosition(CGPoint newCursorPosition);
CGError CGAssociateMouseAndMouseCursorPosition(bool connected);

CGEventMask CGEventMaskBit(CGEventType type)
{
    return cast(CGEventMask) 1 << type;
}

// --- Accessibility (ApplicationServices) -----------------------------------

alias AXUIElementRef = void*;
alias AXError = int;
alias AXValueRef = void*;

enum kAXErrorSuccess = 0;

bool AXIsProcessTrusted();
bool AXIsProcessTrustedWithOptions(CFDictionaryRef options);

AXUIElementRef AXUIElementCreateSystemWide();
AXError AXUIElementCopyAttributeValue(AXUIElementRef element, CFStringRef attribute, CFTypeRef* value);

alias AXValueType = uint;
enum : AXValueType
{
    kAXValueTypeCGPoint = 1,
    kAXValueTypeCGSize  = 2,
    kAXValueTypeCGRect  = 3,
}

bool AXValueGetValue(AXValueRef value, AXValueType theType, void* valuePtr);
