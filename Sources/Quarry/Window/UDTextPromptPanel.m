#import "UDTextPromptPanel.h"

static const CGFloat kUDTextPromptPanelWidth  = 440.0;
static const CGFloat kUDTextPromptPanelHeight = 150.0;

@implementation UDTextPromptPanel {
    NSTextField *_inputField;
}

+ (NSString *)runModalPromptWithTitle:(NSString *)title
                              message:(NSString *)message
                         initialValue:(NSString *)initialValue
                        okButtonTitle:(NSString *)okButtonTitle {
    UDTextPromptPanel *panel = [[self alloc] initWithTitle:title
                                                    message:message
                                               initialValue:initialValue
                                              okButtonTitle:okButtonTitle];
    return [panel _runPrompt];
}

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                 initialValue:(NSString *)initialValue
                okButtonTitle:(NSString *)okButtonTitle {
    self = [super initWithContentRect:NSMakeRect(0.0, 0.0, kUDTextPromptPanelWidth, kUDTextPromptPanelHeight)
                            styleMask:NSWindowStyleMaskTitled
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        self.title = title ?: @"";
        self.releasedWhenClosed = NO; // ARC owns us, not the window machinery

        NSTextField *messageLabel = [[NSTextField alloc] initWithFrame:
            NSMakeRect(16.0, 96.0, kUDTextPromptPanelWidth - 32.0, 44.0)];
        messageLabel.bezeled = NO;
        messageLabel.bordered = NO;
        messageLabel.editable = NO;
        messageLabel.selectable = NO;
        messageLabel.drawsBackground = NO;
        [messageLabel.cell setWraps:YES];
        messageLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        messageLabel.stringValue = message ?: @"";
        [self.contentView addSubview:messageLabel];

        _inputField = [[NSTextField alloc] initWithFrame:
            NSMakeRect(16.0, 60.0, kUDTextPromptPanelWidth - 32.0, 24.0)];
        _inputField.stringValue = initialValue ?: @"";
        [self.contentView addSubview:_inputField];

        NSButton *cancelButton = [[NSButton alloc] initWithFrame:
            NSMakeRect(kUDTextPromptPanelWidth - 196.0, 14.0, 84.0, 30.0)];
        cancelButton.title = @"Cancel";
        [cancelButton setButtonType:NSMomentaryPushInButton];
        cancelButton.bezelStyle = NSRoundedBezelStyle;
        cancelButton.keyEquivalent = @"\033";
        cancelButton.target = self;
        cancelButton.action = @selector(_cancel:);
        [self.contentView addSubview:cancelButton];

        NSButton *okButton = [[NSButton alloc] initWithFrame:
            NSMakeRect(kUDTextPromptPanelWidth - 104.0, 14.0, 88.0, 30.0)];
        okButton.title = okButtonTitle ?: @"OK";
        [okButton setButtonType:NSMomentaryPushInButton];
        okButton.bezelStyle = NSRoundedBezelStyle;
        okButton.keyEquivalent = @"\r";
        okButton.target = self;
        okButton.action = @selector(_ok:);
        [self.contentView addSubview:okButton];
    }
    return self;
}

- (NSString *)_runPrompt {
    [self center];
    [self makeFirstResponder:_inputField];
    [self makeKeyAndOrderFront:nil];
    NSModalResponse response = [NSApp runModalForWindow:self];
    [self orderOut:nil];
    return response == NSModalResponseOK ? _inputField.stringValue : nil;
}

- (void)_ok:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)_cancel:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseCancel];
}

@end
