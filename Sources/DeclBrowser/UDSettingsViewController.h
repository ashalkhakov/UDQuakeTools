#import <Cocoa/Cocoa.h>

@class UDWorkspaceDocument;

@interface UDSettingsViewController : NSWindowController

@property (nonatomic, strong) UDWorkspaceDocument *document;

// Outlets for your UI controls
@property (nonatomic, strong) IBOutlet NSWindow *sheetWindow;
@property (nonatomic, weak) IBOutlet NSTextField *basePathTextField;
@property (nonatomic, weak) IBOutlet NSTextField *gameDirTextField;
@property (nonatomic, weak) IBOutlet NSButton *caseSensitiveCheckbox;

- (IBAction)browseBasePath:(id)sender;
- (IBAction)saveAndDismiss:(id)sender;
- (IBAction)cancelAndDismiss:(id)sender;

@end
