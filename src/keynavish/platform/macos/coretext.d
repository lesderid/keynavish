module keynavish.platform.macos.coretext;

version (OSX):

//
// CoreGraphics drawing and CoreText bindings. Both are plain C APIs, so the
// grid is drawn from D directly; only the window that owns the context comes
// from the Objective-C shim.
//

import keynavish.platform.macos.coregraphics;

extern (C):
nothrow:

// --- CoreGraphics drawing --------------------------------------------------

alias CGContextRef = void*;
alias CGColorRef = void*;
alias CGColorSpaceRef = void*;
alias CGPathRef = void*;
alias CGMutablePathRef = void*;
alias CGAffineTransformRef = void*;

struct CGAffineTransform
{
    CGFloat a, b, c, d, tx, ty;
}

CGColorSpaceRef CGColorSpaceCreateDeviceRGB();
void CGColorSpaceRelease(CGColorSpaceRef space);

CGColorRef CGColorCreateGenericRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha);
CGColorRef CGColorCreate(CGColorSpaceRef space, const(CGFloat)* components);
void CGColorRelease(CGColorRef color);

void CGContextSaveGState(CGContextRef c);
void CGContextRestoreGState(CGContextRef c);

void CGContextSetStrokeColorWithColor(CGContextRef c, CGColorRef color);
void CGContextSetFillColorWithColor(CGContextRef c, CGColorRef color);
void CGContextSetLineWidth(CGContextRef c, CGFloat width);

void CGContextAddRect(CGContextRef c, CGRect rect);
void CGContextAddRects(CGContextRef c, const(CGRect)* rects, size_t count);
void CGContextStrokePath(CGContextRef c);
void CGContextFillRect(CGContextRef c, CGRect rect);
void CGContextBeginPath(CGContextRef c);

void CGContextSetTextMatrix(CGContextRef c, CGAffineTransform t);
void CGContextSetTextPosition(CGContextRef c, CGFloat x, CGFloat y);
void CGContextClearRect(CGContextRef c, CGRect rect);

// --- CoreText --------------------------------------------------------------

alias CTFontRef = void*;
alias CTLineRef = void*;
alias CFAttributedStringRef = void*;
alias CFMutableAttributedStringRef = void*;

CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size, const(CGAffineTransform)* matrix);

CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef string);
void CTLineDraw(CTLineRef line, CGContextRef context);
double CTLineGetTypographicBounds(CTLineRef line, CGFloat* ascent, CGFloat* descent, CGFloat* leading);

extern __gshared CFStringRef kCTFontAttributeName;
extern __gshared CFStringRef kCTForegroundColorAttributeName;

// --- CoreFoundation string/dictionary helpers ------------------------------

// Only ever passed by address, but the layout has to be complete for D to
// declare an extern variable of the type.
struct CFDictionaryKeyCallBacks
{
    CFIndex version_;
    void* retain;
    void* release;
    void* copyDescription;
    void* equal;
    void* hash;
}

struct CFDictionaryValueCallBacks
{
    CFIndex version_;
    void* retain;
    void* release;
    void* copyDescription;
    void* equal;
}

CFDictionaryRef CFDictionaryCreate(CFAllocatorRef allocator,
                                   const(void)** keys, const(void)** values, CFIndex numValues,
                                   const(CFDictionaryKeyCallBacks)* keyCallBacks,
                                   const(CFDictionaryValueCallBacks)* valueCallBacks);

extern __gshared CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks;
extern __gshared CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks;

CFAttributedStringRef CFAttributedStringCreate(CFAllocatorRef alloc, CFStringRef str, CFDictionaryRef attributes);

// --- Offscreen bitmap contexts (used by the render tests) ------------------

alias CGBitmapInfo = uint;
enum : CGBitmapInfo
{
    kCGImageAlphaPremultipliedLast = 1,
    kCGImageAlphaPremultipliedFirst = 2,
    kCGImageAlphaNoneSkipFirst = 6,
}

CGContextRef CGBitmapContextCreate(void* data, size_t width, size_t height,
                                   size_t bitsPerComponent, size_t bytesPerRow,
                                   CGColorSpaceRef space, CGBitmapInfo bitmapInfo);
void* CGBitmapContextGetData(CGContextRef context);
void CGContextRelease(CGContextRef c);
void CGContextTranslateCTM(CGContextRef c, CGFloat tx, CGFloat ty);
void CGContextScaleCTM(CGContextRef c, CGFloat sx, CGFloat sy);
