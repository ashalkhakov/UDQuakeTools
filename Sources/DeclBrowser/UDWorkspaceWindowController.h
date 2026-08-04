//
//  UDWorkspaceWindowController.h
//  PakManager
//
//  Created by artyom on 8/1/26.
//

#import <AppKit/AppKit.h>
#import "UDDeclBrowser.h"

@interface UDWorkspaceWindowController : NSWindowController <UDDeclBrowserDelegate>

@property (weak) IBOutlet NSOutlineView *outlineView;
@property (weak) IBOutlet NSSearchField *nameFilterField;
@property (weak) IBOutlet NSOutlineView *searchOutlineView;
@property (weak) IBOutlet NSSearchField *textFilterField;
@property (weak) IBOutlet NSTextView *textView;
@property (strong) UDDeclBrowser *declBrowser;

- (IBAction)nameFilterChanged:(NSSearchField *)sender;
- (IBAction)textContainsFilterChanged:(NSSearchField *)sender;
@end
