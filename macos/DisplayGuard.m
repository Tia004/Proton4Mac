/* Confine windows only inside Proton4Mac-launched Wine processes. BSD-3-Clause.
 * No global display settings or other applications are modified.
 */
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

static NSScreen *preferredScreen(void) {
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *number = screen.deviceDescription[@"NSScreenNumber"];
        if (CGDisplayIsBuiltin(number.unsignedIntValue)) return screen;
    }
    for (NSScreen *screen in NSScreen.screens)
        if ([screen.localizedName rangeOfString:@"retina" options:NSCaseInsensitiveSearch].location != NSNotFound &&
            [screen.localizedName rangeOfString:@"samsung" options:NSCaseInsensitiveSearch].location == NSNotFound) return screen;
    return nil;
}

static NSRect constrained(NSRect frame) {
    NSScreen *screen = preferredScreen();
    if (!screen) {
        fprintf(stderr, "Proton4Mac: display Retina non disponibile; finestra bloccata.\n");
        return NSMakeRect(-32000, -32000, 1, 1);
    }
    NSRect bounds = screen.visibleFrame;
    frame.size.width = MIN(MAX(frame.size.width, 1), bounds.size.width);
    frame.size.height = MIN(MAX(frame.size.height, 1), bounds.size.height);
    frame.origin.x = MIN(MAX(frame.origin.x, bounds.origin.x), NSMaxX(bounds) - frame.size.width);
    frame.origin.y = MIN(MAX(frame.origin.y, bounds.origin.y), NSMaxY(bounds) - frame.size.height);
    return frame;
}

@interface NSWindow (Proton4MacDisplayGuard)
- (id)p4m_initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing defer:(BOOL)defer;
- (id)p4m_initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing defer:(BOOL)defer screen:(NSScreen *)screen;
- (void)p4m_setFrame:(NSRect)frame display:(BOOL)display;
- (void)p4m_setFrame:(NSRect)frame display:(BOOL)display animate:(BOOL)animate;
- (void)p4m_setFrameOrigin:(NSPoint)origin;
- (void)p4m_orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)other;
@end

@implementation NSWindow (Proton4MacDisplayGuard)
- (id)p4m_initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing defer:(BOOL)defer {
    NSRect frame = constrained([NSWindow frameRectForContentRect:rect styleMask:style]);
    NSWindow *window = [self p4m_initWithContentRect:[NSWindow contentRectForFrameRect:frame styleMask:style] styleMask:style backing:backing defer:defer];
    [window setFrame:constrained(window.frame) display:NO];
    return window;
}
- (id)p4m_initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing defer:(BOOL)defer screen:(NSScreen *)screen {
    NSRect frame = constrained([NSWindow frameRectForContentRect:rect styleMask:style]);
    NSScreen *target = preferredScreen();
    NSWindow *window = [self p4m_initWithContentRect:[NSWindow contentRectForFrameRect:frame styleMask:style] styleMask:style backing:backing defer:defer screen:target];
    [window setFrame:constrained(window.frame) display:NO];
    return window;
}
- (void)p4m_setFrame:(NSRect)frame display:(BOOL)display { [self p4m_setFrame:constrained(frame) display:display]; }
- (void)p4m_setFrame:(NSRect)frame display:(BOOL)display animate:(BOOL)animate { [self p4m_setFrame:constrained(frame) display:display animate:animate]; }
- (void)p4m_setFrameOrigin:(NSPoint)origin {
    NSRect frame = self.frame; frame.origin = origin;
    [self p4m_setFrameOrigin:constrained(frame).origin];
}
- (void)p4m_orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)other {
    if (place != NSWindowOut) {
        NSScreen *screen = preferredScreen();
        if (!screen) return;
        [self setFrame:constrained(self.frame) display:NO];
        NSNumber *number = screen.deviceDescription[@"NSScreenNumber"];
        NSRect frame = self.frame;
        fprintf(stderr, "PROTON4MAC_WINDOW display=%u x=%.0f y=%.0f width=%.0f height=%.0f\n",
                number.unsignedIntValue, frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
    }
    [self p4m_orderWindow:place relativeTo:other];
}
@end

static void swap(SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(NSWindow.class, original);
    Method b = class_getInstanceMethod(NSWindow.class, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor)) static void installGuard(void) {
    @autoreleasepool {
        swap(@selector(initWithContentRect:styleMask:backing:defer:), @selector(p4m_initWithContentRect:styleMask:backing:defer:));
        swap(@selector(initWithContentRect:styleMask:backing:defer:screen:), @selector(p4m_initWithContentRect:styleMask:backing:defer:screen:));
        swap(@selector(setFrame:display:), @selector(p4m_setFrame:display:));
        swap(@selector(setFrame:display:animate:), @selector(p4m_setFrame:display:animate:));
        swap(@selector(setFrameOrigin:), @selector(p4m_setFrameOrigin:));
        swap(@selector(orderWindow:relativeTo:), @selector(p4m_orderWindow:relativeTo:));
    }
}

/* Wine must not change modes or capture the external display either. */
static CGError guardedCapture(CGDirectDisplayID display) {
    return CGDisplayIsBuiltin(display) ? CGDisplayCapture(display) : kCGErrorCannotComplete;
}
static CGError guardedCaptureOptions(CGDirectDisplayID display, CGCaptureOptions options) {
    return CGDisplayIsBuiltin(display) ? CGDisplayCaptureWithOptions(display, options) : kCGErrorCannotComplete;
}
static CGError guardedSetMode(CGDirectDisplayID display, CGDisplayModeRef mode, CFDictionaryRef options) {
    return CGDisplayIsBuiltin(display) ? CGDisplaySetDisplayMode(display, mode, options) : kCGErrorCannotComplete;
}
static CGError guardedConfigureMode(CGDisplayConfigRef config, CGDirectDisplayID display, CGDisplayModeRef mode, CFDictionaryRef options) {
    return CGDisplayIsBuiltin(display) ? CGConfigureDisplayWithDisplayMode(config, display, mode, options) : kCGErrorCannotComplete;
}
static CGError guardedCaptureAll(void) { return kCGErrorCannotComplete; }
static CGError guardedCaptureAllOptions(CGCaptureOptions options) { return kCGErrorCannotComplete; }
#define INTERPOSE(replacement, original) { (const void *)(replacement), (const void *)(original) }
__attribute__((used)) static const struct { const void *replacement; const void *original; }
interpositions[] __attribute__((section("__DATA,__interpose"))) = {
    INTERPOSE(guardedCapture, CGDisplayCapture),
    INTERPOSE(guardedCaptureOptions, CGDisplayCaptureWithOptions),
    INTERPOSE(guardedSetMode, CGDisplaySetDisplayMode),
    INTERPOSE(guardedConfigureMode, CGConfigureDisplayWithDisplayMode),
    INTERPOSE(guardedCaptureAll, CGCaptureAllDisplays),
    INTERPOSE(guardedCaptureAllOptions, CGCaptureAllDisplaysWithOptions)
};
