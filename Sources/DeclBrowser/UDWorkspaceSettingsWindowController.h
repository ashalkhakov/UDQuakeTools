#import <AppKit/AppKit.h>

@class UDWorkspaceDocument;

@interface UDWorkspaceSettingsWindowController : NSWindowController

@property (weak) IBOutlet NSTextField *basepathField;
@property (weak) IBOutlet NSTextField *gameField;
@property (weak) IBOutlet NSButton *caseSensitiveFSCheckbox;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)selectBasePath:(id)sender;

@end

