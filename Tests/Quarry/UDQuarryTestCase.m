#import "UDQuarryTestCase.h"
#import <objc/runtime.h>
#import "UDDeclEditorViewController.h"
#import "UDReferencePicker.h"

#import "UQExtension.h"
#import "UQProject.h"
#import "UDWorkspaceItem.h"
#import "UDGameWorkspace.h"
#import "UDBaseDocument.h"

NSString *UDDoom3InstallPath(void) {
    NSString *path = [[NSProcessInfo processInfo] environment][@"UD_DOOM3_PATH"];
    if (path.length == 0) {
        path = @"/Volumes/ExtraSSD/games/DOOM 3";
    }
    NSString *pak = [[path stringByAppendingPathComponent:@"base"] stringByAppendingPathComponent:@"pak000.pk4"];
    return [[NSFileManager defaultManager] isReadableFileAtPath:pak] ? path : nil;
}

@interface UDQuarryTestCase ()
@property (nonatomic, copy, readwrite) NSString *scratchDirectory;
@property (nonatomic, strong) NSMutableArray<UQTestWindow *> *openWindows;
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

@implementation UDQuarryTestCase

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
    self.openWindows = [NSMutableArray array];
}

- (void)tearDown {
    for (UQTestWindow *window in [self.openWindows copy]) {
        [self closeWorkspace:window];
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

- (UQTestWindow *)openWorkspaceWithSettings:(NSDictionary *)settings {
    // a project's folder, its .qworkspace those settings
    NSString *folder = [self.scratchDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"project-%lu",
                                                                              (unsigned long)self.openWindows.count]];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:settings options:0 error:&error];
    if (![json writeToFile:[folder stringByAppendingPathComponent:@"mod.qworkspace"] atomically:YES]) {
        XCTFail(@"the workspace settings were not written: %@", error);
        return nil;
    }
    UQExtension *extension = [[UQExtension alloc] init];
    [extension extensionDidLoad:[NSBundle bundleForClass:[UQExtension class]]];
    UQTestWindow *window = [UQTestWindow windowOfFolder:folder extension:extension timeout:60 error:&error];
    if (window == nil) {
        XCTFail(@"the game of %@ did not start: %@", settings[@"fs_basepath"], error);
        return nil;
    }
    [self.openWindows addObject:window];
    [window.window setFrame:NSMakeRect(0, 0, 1280, 800) display:YES];
    [self spinUntil:^BOOL{ return NO; } timeout:0.05];
    return window;
}

- (void)closeWorkspace:(UQTestWindow *)controller {
    [controller close];
    [self.openWindows removeObject:controller];
}

- (UQTestWindow *)tabManagerOf:(UQTestWindow *)controller {
    return controller;
}

#pragma mark - Outline

/// A row's label, as the tree shows it.
- (NSString *)labelOfItem:(id)item inOutline:(NSOutlineView *)outline {
    return [outline.dataSource outlineView:outline objectValueForTableColumn:outline.tableColumns.firstObject byItem:item];
}

- (NSInteger)rowOfItemNamed:(NSString *)name parent:(id)parent inOutline:(NSOutlineView *)outline {
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        id item = [outline itemAtRow:row];
        if ([outline parentForItem:item] == parent && [[self labelOfItem:item inOutline:outline] isEqualToString:name]) {
            return row;
        }
    }
    return -1;
}

- (NSInteger)revealOutlinePath:(NSString *)path inController:(UQTestWindow *)controller {
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

/// Chosen in the tree: its command (open the item's URL) opens its tab.
- (UDBaseEditorViewController *)openOutlinePath:(NSString *)path inController:(UQTestWindow *)controller {
    NSInteger row = [self revealOutlinePath:path inController:controller];
    if (row < 0) {
        return nil;
    }
    [controller.window makeFirstResponder:controller.outlineView];
    [controller.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                        byExtendingSelection:NO];
    [self spinUntil:^BOOL{ return NO; } timeout:0.05];

    // its tab: a Quarry editor's (a structured decl's, a GUI's), or a text
    // document's (a script's, a decl's of no editor of its own: UDCode's editor)
    UDBaseEditorViewController *editor = controller.selectedEditor;
    NSURL *url = controller.selectedDocument.URL;
    NSString *typeName = nil, *name = nil, *gamePath = nil;
    [UQProject parseURL:url typeName:&typeName name:&name path:&gamePath];
    NSString *opened = gamePath ?: (typeName ? [NSString stringWithFormat:@"%@/%@", typeName, name] : nil);
    if (opened == nil) {
        XCTFail(@"choosing %@ in the outline opened no tab", path);
    } else if (![opened isEqualToString:path]) {
        XCTFail(@"choosing %@ opened a tab for %@ instead", path, opened);
    }
    return editor;
}

- (void)collectPathsUnder:(id)item prefix:(NSString *)prefix
                  outline:(NSOutlineView *)outline into:(NSMutableArray *)paths {
    id<NSOutlineViewDataSource> source = outline.dataSource;
    NSInteger count = [source outlineView:outline numberOfChildrenOfItem:item];
    for (NSInteger i = 0; i < count; i++) {
        id child = [source outlineView:outline child:i ofItem:item];
        NSString *label = [self labelOfItem:child inOutline:outline];
        NSString *path = prefix.length ? [prefix stringByAppendingFormat:@"/%@", label] : label;
        [paths addObject:path];
        [self collectPathsUnder:child prefix:path outline:outline into:paths];
    }
}

- (NSArray<NSString *> *)expandedOutlinePathsInController:(UQTestWindow *)controller {
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

- (NSView *)viewBoundTo:(NSString *)key inView:(NSView *)view {
    return [self viewBoundTo:key ofClass:[NSView class] inView:view];
}

- (NSView *)viewBoundTo:(NSString *)key ofClass:(Class)cls inView:(NSView *)view {
    NSString *keyPath = [@"selection." stringByAppendingString:key];
    __block NSView *found = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if (![candidate isKindOfClass:cls]) return YES;
        for (NSString *binding in @[NSValueBinding, NSSelectedValueBinding, NSSelectedIndexBinding]) {
            if ([[candidate infoForBinding:binding][NSObservedKeyPathKey] isEqualToString:keyPath]) {
                found = candidate;
                return NO;
            }
        }
        return YES;
    }];
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

- (NSView *)viewWithToolTip:(NSString *)toolTip inView:(NSView *)view {
    __block NSView *found = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if ([candidate.toolTip isEqualToString:toolTip]) found = candidate;
        return found == nil;
    }];
    return found;
}

- (NSSegmentedControl *)segmentedControlWithAction:(SEL)action inView:(NSView *)view {
    __block NSSegmentedControl *found = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if ([candidate isKindOfClass:[NSSegmentedControl class]] &&
            sel_isEqual([(NSSegmentedControl *)candidate action], action)) {
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
    // A field the window started in is being edited already, and GNUstep's
    // refuses to become first responder again while it is.
    if ([field currentEditor] == nil) {
        XCTAssertTrue([window makeFirstResponder:field], @"the field should take focus");
    }
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

#pragma mark - Pickers

/// The "…" of @a tag under @a view clicked, and @a choose run on its
/// picker (a sheet; a modal window on GNUstep).
- (void)pick:(NSInteger)tag in:(UDDeclEditorViewController *)editor under:(NSView *)view
        with:(void (^)(UDReferencePicker *picker))choose {
    [self pick:tag action:@selector(pickReference:) under:view sheetOver:editor.view.window
          with:choose picker:^UDReferencePicker *{ return editor.referencePicker; }];
}

- (void)pick:(NSInteger)tag action:(SEL)action under:(NSView *)view sheetOver:(NSWindow *)window
        with:(void (^)(UDReferencePicker *picker))choose picker:(UDReferencePicker *(^)(void))picker {
    __block NSButton *button = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if ([candidate isKindOfClass:[NSButton class]] && sel_isEqual([(NSButton *)candidate action], action)
            && [(NSButton *)candidate tag] == tag) {
            button = (NSButton *)candidate;
            return NO;
        }
        return YES;
    }];
    XCTAssertNotNil(button, @"a picker's button, tag %ld", (long)tag);
    __block BOOL shown = NO;
#ifdef GNUSTEP
    [self whenModalWindowAppears:^(NSWindow *window) {
        shown = YES;
        choose((UDReferencePicker *)window.windowController);
    }];
    [NSApp sendAction:button.action to:button.target from:button];
#else
    [NSApp sendAction:button.action to:button.target from:button];
    NSWindow *sheet = window.attachedSheet;
    XCTAssertNotNil(sheet, @"a sheet");
    if (sheet != nil) {
        shown = YES;
        choose(picker());
    }
    [self spinUntil:^BOOL{ return window.attachedSheet == nil; } timeout:5];
#endif
    XCTAssertTrue(shown);
}

/// The picker's @a name chosen, and OK.
- (void)choose:(NSString *)name in:(UDReferencePicker *)picker {
    NSUInteger row = [picker.shownNames indexOfObject:name];
    XCTAssertNotEqual(row, (NSUInteger)NSNotFound, @"%@ among %@", name, picker.shownNames);
    if (row == NSNotFound) {
        [picker cancel:nil];
        return;
    }
    [picker.table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [picker ok:nil];
}

- (void)click:(SEL)action tag:(NSInteger)tag under:(NSView *)view sheetOver:(NSWindow *)window
         with:(void (^)(id controller))block {
    __block NSButton *button = nil;
    [self forEachViewUnder:view do:^BOOL(NSView *candidate) {
        if ([candidate isKindOfClass:[NSButton class]] && sel_isEqual([(NSButton *)candidate action], action) && [(NSButton *)candidate tag] == tag) {
            button = (NSButton *)candidate;
            return NO;
        }
        return YES;
    }];
    XCTAssertNotNil(button, @"a button of %@, tag %ld", NSStringFromSelector(action), (long)tag);
    __block BOOL shown = NO;
#ifdef GNUSTEP
    [self whenModalWindowAppears:^(NSWindow *sheet) {
        shown = YES;
        block(sheet.windowController);
    }];
    [NSApp sendAction:button.action to:button.target from:button];
#else
    [NSApp sendAction:button.action to:button.target from:button];
    NSWindow *sheet = window.attachedSheet;
    XCTAssertNotNil(sheet, @"a sheet");
    if (sheet != nil) {
        shown = YES;
        block(sheet.windowController);
    }
    [self spinUntil:^BOOL{ return window.attachedSheet == nil; } timeout:5];
#endif
    XCTAssertTrue(shown);
}

@end
