#import "UDDeclBrowserTestCase.h"

#import "UDWorkspaceDocument.h"
#import "UDEditorTabManager.h"
#import "UDWorkspaceItem.h"
#import "UDWorkspace.h"
#import "UDBaseDocument.h"

NSString *UDDoom3InstallPath(void) {
    NSString *path = [[NSProcessInfo processInfo] environment][@"UD_DOOM3_PATH"];
    if (path.length == 0) {
        path = @"/Volumes/ExtraSSD/games/DOOM 3";
    }
    NSString *pak = [[path stringByAppendingPathComponent:@"base"] stringByAppendingPathComponent:@"pak000.pk4"];
    return [[NSFileManager defaultManager] isReadableFileAtPath:pak] ? path : nil;
}

@interface UDDeclBrowserTestCase ()
@property (nonatomic, copy, readwrite) NSString *scratchDirectory;
@property (nonatomic, strong) NSMutableArray<UDWorkspaceDocument *> *openDocuments;
@end

/// Runs a block once a modal window is up, then sees the modal through.
/// (A timer target rather than a block timer: GNUstep marks the block
/// timer API non-portable.)
@interface UDModalDriver : NSObject
@property (nonatomic, copy) void (^fail)(NSString *reason);
@property (nonatomic, copy) void (^block)(NSWindow *window);
@property (nonatomic, strong) NSDate *giveUp;
@property (nonatomic) BOOL ran;
@end

@implementation UDModalDriver

- (void)tick:(NSTimer *)timer {
    NSWindow *modal = [NSApp modalWindow];
    if (!self.ran && modal != nil) {
        self.ran = YES;
        self.block(modal);
        // -stopModalWithCode: (what OK and Cancel send) only takes effect
        // when the modal loop next gets an event; with a real mouse the
        // click's own events wake it, here nothing would. Stand in for them.
        [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined
                                            location:NSZeroPoint
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:modal.windowNumber
                                             context:nil
                                             subtype:0
                                               data1:0
                                               data2:0]
                 atStart:NO];
        return;
    }
    if (self.ran && modal == nil) {
        [timer invalidate];
    } else if ([self.giveUp timeIntervalSinceNow] <= 0) {
        [timer invalidate];
        if (modal != nil) {
            self.fail(@"a modal window was still up after 20 seconds; aborting it");
            [NSApp abortModal];
        } else {
            self.fail(@"no modal window appeared");
        }
    }
}

@end

@implementation UDDeclBrowserTestCase

// Per case rather than +setUp: GNUstep's XCTest does not call +setUp, and
// nothing that touches a font may run before the shared application exists.
// -sharedApplication is idempotent.
- (void)setUp {
    [super setUp];
    [NSApplication sharedApplication];

    NSString *name = [NSString stringWithFormat:@"declbrowser-tests-%@", [[NSUUID UUID] UUIDString]];
    self.scratchDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.scratchDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    self.openDocuments = [NSMutableArray array];
}

- (void)tearDown {
    for (UDWorkspaceDocument *document in [self.openDocuments copy]) {
        [self closeDocument:document];
    }
    [[NSFileManager defaultManager] removeItemAtPath:self.scratchDirectory error:NULL];
    [super tearDown];
}

#pragma mark - Workspaces

- (NSDictionary *)workspaceSettingsWithBasePath:(NSString *)basePath savePath:(NSString *)savePath {
    return @{
        @"fs_basepath": basePath,
        @"fs_savepath": savePath,
        @"fs_homepath": savePath,
        @"fs_cdpath": @"",
        @"fs_game": @"base",
        @"fs_game_base": @"",
        @"gamedir": @"base",
        @"pakFileExtension": @"pk4",
        @"fs_debug": @NO,
        @"fs_restrict": @NO,
        @"fs_copyfiles": @0,
        @"fs_caseSensitiveOS": @YES,
        @"decl_show": @0,
        @"com_SingleDeclFile": @NO,
        @"com_singleDeclFileName": @"",
        @"com_singleDeclFileWriteMode": @1,
    };
}

- (UDWorkspaceWindowController *)openWorkspaceWithSettings:(NSDictionary *)settings {
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:settings options:0 error:&error];
    UDWorkspaceDocument *document = [[UDWorkspaceDocument alloc] init];
    if (![document readFromData:json ofType:@"com.udquake.qworkspace" error:&error]) {
        XCTFail(@"the workspace settings did not read: %@", error);
        return nil;
    }

    [document makeWindowControllers];
    UDWorkspaceWindowController *controller = nil;
    for (NSWindowController *candidate in document.windowControllers) {
        if ([candidate isKindOfClass:[UDWorkspaceWindowController class]]) {
            controller = (UDWorkspaceWindowController *)candidate;
        }
    }
    if (controller == nil) {
        XCTFail(@"the workspace for %@ did not start, so no workspace window was made",
                settings[@"fs_basepath"]);
        return nil;
    }
    [self.openDocuments addObject:document];

    if (controller.window == nil) {
        XCTFail(@"%@", @"the workspace window did not load from UDWorkspaceWindow.xib");
        return nil;
    }
    [document showWindows];
    [controller.window setFrame:NSMakeRect(0, 0, 1280, 800) display:YES];
    [self spinUntil:^BOOL{ return NO; } timeout:0.05];
    return controller;
}

- (void)closeDocument:(UDWorkspaceDocument *)document {
    for (UDBaseEditorViewController *editor in [[self tabManagerOfDocument:document] allEditors]) {
        [editor.editorDocument close];
    }
    [[self tabManagerOfDocument:document] closeAllTabs];
    [document.workspace shutdown];
    [document close];
    [self.openDocuments removeObject:document];
}

- (UDEditorTabManager *)tabManagerOfDocument:(UDWorkspaceDocument *)document {
    for (NSWindowController *candidate in document.windowControllers) {
        if ([candidate isKindOfClass:[UDWorkspaceWindowController class]]) {
            return [self tabManagerOf:(UDWorkspaceWindowController *)candidate];
        }
    }
    return nil;
}

- (void)closeWorkspace:(UDWorkspaceWindowController *)controller {
    [self closeDocument:controller.document];
}

- (UDEditorTabManager *)tabManagerOf:(UDWorkspaceWindowController *)controller {
    return [controller valueForKey:@"tabManager"];
}

#pragma mark - Outline

- (NSInteger)rowOfItemNamed:(NSString *)name parent:(id)parent inOutline:(NSOutlineView *)outline {
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        UDWorkspaceItem *item = [outline itemAtRow:row];
        if ([outline parentForItem:item] == parent && [item.name isEqualToString:name]) {
            return row;
        }
    }
    return -1;
}

- (NSInteger)revealOutlinePath:(NSString *)path inController:(UDWorkspaceWindowController *)controller {
    NSOutlineView *outline = controller.outlineView;
    id parent = nil;
    NSInteger row = -1;
    for (NSString *component in [path componentsSeparatedByString:@"/"]) {
        if (parent != nil) {
            [outline expandItem:parent];
        }
        row = [self rowOfItemNamed:component parent:parent inOutline:outline];
        if (row < 0) {
            XCTFail(@"the outline has no “%@” on the way to %@", component, path);
            return -1;
        }
        parent = [outline itemAtRow:row];
    }
    [outline scrollRowToVisible:row];
    return row;
}

- (UDBaseEditorViewController *)openOutlinePath:(NSString *)path inController:(UDWorkspaceWindowController *)controller {
    NSInteger row = [self revealOutlinePath:path inController:controller];
    if (row < 0) {
        return nil;
    }
    [controller.window makeFirstResponder:controller.outlineView];
    [controller.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                        byExtendingSelection:NO];
    [self spinUntil:^BOOL{ return NO; } timeout:0.05];

    UDBaseEditorViewController *editor = [[self tabManagerOf:controller] selectedEditor];
    if (editor == nil) {
        XCTFail(@"selecting %@ in the outline opened no editor tab", path);
    } else if (![editor.item.path isEqualToString:path]) {
        XCTFail(@"selecting %@ opened a tab for %@ instead", path, editor.item.path);
    }
    return editor;
}

- (void)collectPathsUnder:(id)item prefix:(NSString *)prefix
                  outline:(NSOutlineView *)outline into:(NSMutableArray *)paths {
    id<NSOutlineViewDataSource> source = outline.dataSource;
    NSInteger count = [source outlineView:outline numberOfChildrenOfItem:item];
    for (NSInteger i = 0; i < count; i++) {
        UDWorkspaceItem *child = [source outlineView:outline child:i ofItem:item];
        NSString *path = prefix.length ? [prefix stringByAppendingFormat:@"/%@", child.name] : child.name;
        [paths addObject:path];
        [self collectPathsUnder:child prefix:path outline:outline into:paths];
    }
}

- (NSArray<NSString *> *)expandedOutlinePathsInController:(UDWorkspaceWindowController *)controller {
    NSMutableArray *paths = [NSMutableArray array];
    [self collectPathsUnder:nil prefix:@"" outline:controller.outlineView into:paths];
    return paths;
}

#pragma mark - Run loop

- (void)finishEvent {
    NSString *mode = [[NSRunLoop currentRunLoop] currentMode] ?: NSDefaultRunLoopMode;
    [[NSRunLoop currentRunLoop] runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

- (BOOL)spinUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition()) {
        if ([deadline timeIntervalSinceNow] <= 0) {
            return NO;
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return YES;
}

#pragma mark - Finding views

- (void)forEachViewUnder:(NSView *)view do:(BOOL (^)(NSView *view))visit {
    NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:view];
    while (queue.count > 0) {
        NSView *current = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (!visit(current)) {
            return;
        }
        [queue addObjectsFromArray:current.subviews];
    }
}

- (NSTextField *)textFieldBoundTo:(NSString *)key inView:(NSView *)view {
    NSString *keyPath = [@"selection." stringByAppendingString:key];
    __block NSTextField *found = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if ([candidate isKindOfClass:[NSTextField class]] &&
            [[candidate infoForBinding:NSValueBinding][NSObservedKeyPathKey] isEqualToString:keyPath]) {
            found = (NSTextField *)candidate;
            return NO;
        }
        return YES;
    }];
    XCTAssertNotNil(found, @"there should be a text field bound to %@", keyPath);
    return found;
}

- (NSButton *)buttonTitled:(NSString *)title inView:(NSView *)view {
    __block NSButton *found = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if ([candidate isKindOfClass:[NSButton class]] && [[(NSButton *)candidate title] isEqualToString:title]) {
            found = (NSButton *)candidate;
            return NO;
        }
        return YES;
    }];
    return found;
}

- (NSView *)firstSubviewOfClass:(Class)cls inView:(NSView *)view {
    __block NSView *found = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if ([candidate isKindOfClass:cls]) {
            found = candidate;
            return NO;
        }
        return YES;
    }];
    return found;
}

- (NSSegmentedControl *)segmentedControlWithAction:(SEL)action inView:(NSView *)view {
    __block NSSegmentedControl *found = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if ([candidate isKindOfClass:[NSSegmentedControl class]] &&
            [(NSSegmentedControl *)candidate action] == action) {
            found = (NSSegmentedControl *)candidate;
            return NO;
        }
        return YES;
    }];
    return found;
}

- (void)selectTabLabeled:(NSString *)label inView:(NSView *)view {
    __block NSTabViewItem *found = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if ([candidate isKindOfClass:[NSTabView class]]) {
            for (NSTabViewItem *item in [(NSTabView *)candidate tabViewItems]) {
                if ([item.label isEqualToString:label]) {
                    found = item;
                    return NO;
                }
            }
        }
        return YES;
    }];
    XCTAssertNotNil(found, @"there should be a “%@” tab", label);
    [found.tabView selectTabViewItem:found];
    [self finishEvent];
}

#pragma mark - Typing

- (void)typeText:(NSString *)text intoField:(NSTextField *)field {
    NSWindow *window = field.window;
    XCTAssertNotNil(window, @"the field must be in a window to be typed into");
    XCTAssertTrue([window makeFirstResponder:field], @"the field should take focus");
    NSText *editor = [field currentEditor];
    XCTAssertNotNil(editor, @"a focused text field should have a field editor");
    [editor selectAll:nil];
    [editor insertText:text];
    // Tab away: ending editing is what pushes the value through the binding.
    XCTAssertTrue([window makeFirstResponder:nil],
                  @"“%@” should be accepted when editing ends (nothing in the field may reject it)", text);
    [self finishEvent];
}

- (void)typeText:(NSString *)text intoTextView:(NSTextView *)textView {
    XCTAssertTrue([textView.window makeFirstResponder:textView], @"the text view should take focus");
    [textView selectAll:nil];
    [textView insertText:text];
}

#pragma mark - Modal sessions

- (void)whenModalWindowAppears:(void (^)(NSWindow *window))block {
    UDModalDriver *driver = [[UDModalDriver alloc] init];
    __weak typeof(self) weakSelf = self;
    driver.fail = ^(NSString *reason) {
        typeof(self) self = weakSelf;
        XCTFail(@"%@", reason);
    };
    driver.block = block;
    driver.giveUp = [NSDate dateWithTimeIntervalSinceNow:20];
    // The timer retains the driver until the driver invalidates it.
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.05 target:driver selector:@selector(tick:)
                                           userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
}

@end
