#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSScreen *target = nil, *other = nil;
        for (NSScreen *screen in NSScreen.screens) {
            if (CGDisplayIsBuiltin([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue])) target = screen;
            else other = screen;
        }
        if (!target) return 77;
        NSRect requested = other ? other.frame : NSOffsetRect(target.frame, 10000, 10000);
        requested.size = NSMakeSize(640, 480);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:requested styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        BOOL initial = NSContainsRect(target.visibleFrame, window.frame);
        [window setFrame:requested display:NO];
        BOOL resize = NSContainsRect(target.visibleFrame, window.frame);
        [window setFrameOrigin:requested.origin];
        BOOL move = NSContainsRect(target.visibleFrame, window.frame);
        [window setFrame:requested display:NO animate:NO];
        BOOL animation = NSContainsRect(target.visibleFrame, window.frame);
        NSDictionary *result = @{@"initial": @(initial), @"resize": @(resize), @"move": @(move), @"animation": @(animation), @"target": target.localizedName,
                                 @"visible_windows_created": @NO};
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        return initial && resize && move && animation ? 0 : 1;
    }
}
