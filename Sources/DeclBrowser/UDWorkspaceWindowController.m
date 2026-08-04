//
//  UDWorkspaceWindowController.m
//  PakManager
//
//  Created by artyom on 8/1/26.
//

#import "idFileSystem.h"
#import "idDeclManager.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceDocument.h"
#import "UDDeclBrowser.h"

@implementation UDWorkspaceWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    
    self.outlineView.dataSource = self;
    self.outlineView.delegate = self;
    
    // Optional: make the text view a bit nicer
    self.textView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.textView.automaticQuoteSubstitutionEnabled = NO;

    // Let the window finish becoming visible & key first
    dispatch_async(dispatch_get_main_queue(), ^{
        UDWorkspaceDocument *doc = (UDWorkspaceDocument *)self.document;
        if (doc.fileURL == nil && ![doc isConfigured]) {
            if ([doc showSettingsForced]) {
                [self attachDeclBrowser];
            }
        } else {
            [self attachDeclBrowser];
        }
    });
}

-(void)attachDeclBrowser {
    self.declBrowser = [[UDDeclBrowser alloc] initWithWorkspace:self.workspace];
    self.declBrowser.delegate = self;

    [self.declBrowser attachToOutlineViews:self.outlineView searchOutline:self.searchOutlineView];
    [self.declBrowser reset];          // builds the full tree
}

-(UDWorkspace *)workspace {
    return ((UDWorkspaceDocument *)self.document).workspace;
}

//
// text editing
//

- (void)textDidChange:(NSNotification *)notification {
#if 0
    id selected = /* currently selected decl */;
    if (selected) {
        [self.document setText:self.textView.string forDecl:selected];
        [self.document updateChangeCount:NSChangeDone];
    }
#endif
}

- (IBAction)nameFilterChanged:(NSSearchField *)sender {
    NSString *name = sender.stringValue;
    
    [self.declBrowser findByName:(name.length ? name : @"*")];
}

- (IBAction)textContainsFilterChanged:(NSSearchField *)sender {
    NSString *name = sender.stringValue;
    
    [self.declBrowser findContaining:name ?: @""];
}

#pragma mark - UDDeclBrowserDelegate

- (void)declBrowser:(UDDeclBrowser *)browser didSelectDecl:(const idDecl *)decl {
    if (!decl) {
        self.textView.string = @"";
        return;
    }
    
    NSMutableData *text = [[NSMutableData alloc] init];
    [decl text:text];
    NSString *textStr = [NSString stringWithUTF8String:text.bytes];
    
    self.textView.string = textStr ?: @"";
    
    // Optional nice touches
    [self.textView setSelectedRange:NSMakeRange(0, 0)];
    [self.textView scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)declBrowser:(UDDeclBrowser *)browser didSelectGuiOrScript:(NSString *)fileName {
    if (!fileName || fileName.length == 0) {
        self.textView.string = @"";
        return;
    }
    
    UDWorkspace *workspace = ((UDWorkspaceDocument *)self.document).workspace;
    
    void *buffer = NULL;
    int bufferLen = [workspace.fileSystem readFile:fileName buffer:&buffer timestamp:NULL error:nil];
    
    if (!bufferLen) {
        self.textView.string = @"";
        return;
    }
    
    NSString *text = [[NSString alloc] initWithBytes:buffer length:bufferLen encoding:NSUTF8StringEncoding];
    [workspace.fileSystem freeFile:buffer error:nil];
    self.textView.string = text;
}

- (void)declBrowserDidClearSelection:(UDDeclBrowser *)browser {
    self.textView.string = @"";
}

@end
