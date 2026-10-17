#import "UDWorkspaceOpeningController.h"

@implementation UDWorkspaceOpeningController {
    NSString *_name;
}

- (instancetype)initWithWorkspaceName:(NSString *)name {
    self = [super initWithWindowNibName:@"UDWorkspaceOpening"];
    if (self) {
        _name = [name copy];
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.messageField.stringValue = [NSString stringWithFormat:@"Opening “%@”…", _name];
}

- (void)showOverWindow:(nullable NSWindow *)window {
    NSWindow *panel = self.window;
    if (window != nil) {
        NSRect over = window.frame, frame = panel.frame;
        [panel setFrameOrigin:NSMakePoint(NSMidX(over) - NSWidth(frame) / 2, NSMidY(over) - NSHeight(frame) / 2)];
    } else {
        [panel center];
    }
    [self.progressIndicator startAnimation:nil];
    [panel orderFront:nil];
}

- (void)close {
    [self.progressIndicator stopAnimation:nil];
    [super close];
}

@end
