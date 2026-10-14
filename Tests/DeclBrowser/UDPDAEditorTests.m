#import "UDDeclBrowserTestCase.h"

#import "UDDeclManagedObjects.h"
#import "UDDeclDocument.h"
#import "UDEditorTabManager.h"
#import "UDPDAEditorViewController.h"

static NSString *const UDFixturePDA =
    @"pda udtest_pda {\n"
     "\tname\t\t\"Ian McCormick\"\n"
     "\tfullname\t\"Ian A. McCormick\"\n"
     "\ticon\t\t\"gui/pda/bio1\"\n"
     "\tid\t\t\"4122-36\"\n"
     "\tpost\t\t\"Mars City\"\n"
     "\ttitle\t\t\"Technician\"\n"
     "\tsecurity\t\"\"\n"
     "\tpda_email\t\"udtest_pda_email_1\"\n"
     "\tpda_audio\t\"udtest_pda_audio_1\"\n"
     "}\n"
     "\n"
     "email udtest_pda_email_1 {\n"
     "\tdate\t\"11-14-2145\"\n"
     "\tto\t\"Ian McCormick\"\n"
     "\tfrom\t\"Elliot Swann\"\n"
     "\tsubject\t\"Delta Labs\"\n"
     "\ttext {\n"
     "\"Report to Delta Labs at once.\"\n"
     "\t}\n"
     "}\n"
     "\n"
     "audio udtest_pda_audio_1 {\n"
     "\taudio\t\"pdas/udtest/audio1\"\n"
     "\tname\t\"Shift Report\"\n"
     "\tinfo\t\"Recorded at the start of the shift.\"\n"
     "}\n";

/**
 * The PDA editor, driven against a loose PDA decl file (no game data
 * needed, so these run everywhere). Each case opens the PDA from the
 * browser outline, edits it through the editor's own controls — fields,
 * segmented +/- buttons, the child decl editor sheets — saves with File >
 * Save, and checks the decl file that was written and what a freshly
 * opened workspace reads back.
 */
@interface UDPDAEditorTests : UDDeclBrowserTestCase
@property (nonatomic, copy) NSString *basePath;
@property (nonatomic, copy) NSString *savePath;
@end

@implementation UDPDAEditorTests

- (void)setUp {
    [super setUp];
    self.basePath = [self.scratchDirectory stringByAppendingPathComponent:@"install"];
    self.savePath = [self.scratchDirectory stringByAppendingPathComponent:@"save"];

    NSString *pdaDirectory = [self.basePath stringByAppendingPathComponent:@"base/newpdas"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pdaDirectory
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.savePath
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [UDFixturePDA writeToFile:[pdaDirectory stringByAppendingPathComponent:@"udtest.pda"]
                   atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (UDWorkspaceWindowController *)openFixtureWorkspace {
    return [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:self.basePath
                                                                      savePath:self.savePath]];
}

- (UDPDAEditorViewController *)openFixturePDAIn:(UDWorkspaceWindowController *)controller {
    UDBaseEditorViewController *editor = [self openOutlinePath:@"pda/udtest_pda" inController:controller];
    if (![editor isKindOfClass:[UDPDAEditorViewController class]]) {
        XCTFail(@"a pda decl should open in the PDA editor, not %@", editor);
        return nil;
    }
    UDPDAEditorViewController *pdaEditor = (UDPDAEditorViewController *)editor;
    XCTAssertNotNil(pdaEditor.pda, @"the PDA editor should have loaded the decl");
    return pdaEditor;
}

/// The text of the decl file the last save produced: the copy under the
/// save path when there is one (that is the one the game loads first),
/// otherwise the original.
- (NSString *)savedPDAFileText {
    for (NSString *root in @[self.savePath, self.basePath]) {
        NSString *path = [root stringByAppendingPathComponent:@"base/newpdas/udtest.pda"];
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (text != nil) {
            return text;
        }
    }
    XCTFail(@"%@", @"no newpdas/udtest.pda found after saving");
    return @"";
}

/// The text of one decl ("pda udtest_pda") in a decl file: from its header
/// to the closing brace at the start of a line.
- (NSString *)declNamed:(NSString *)header inText:(NSString *)text {
    NSRange start = [text rangeOfString:[header stringByAppendingString:@" {"]];
    if (start.location == NSNotFound) {
        XCTFail(@"no “%@” in:\n%@", header, text);
        return @"";
    }
    NSRange end = [text rangeOfString:@"\n}" options:0 range:NSMakeRange(start.location, text.length - start.location)];
    NSUInteger stop = end.location == NSNotFound ? text.length : NSMaxRange(end);
    return [text substringWithRange:NSMakeRange(start.location, stop - start.location)];
}

- (void)save:(UDWorkspaceWindowController *)controller {
    [NSApp sendAction:@selector(saveDocument:) to:controller from:nil];
    [self spinUntil:^BOOL{ return NO; } timeout:0.1];
}

#pragma mark -

- (void)testThePDAOpensFromTheOutlineWithItsFieldsFilledIn {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDPDAEditorViewController *editor = [self openFixturePDAIn:controller];
    if (editor == nil) return;

    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:editor.view].stringValue, @"Ian A. McCormick");
    XCTAssertEqualObjects([self textFieldBoundTo:@"pdaName" inView:editor.view].stringValue, @"Ian McCormick");
    XCTAssertEqualObjects([self textFieldBoundTo:@"ident" inView:editor.view].stringValue, @"4122-36");
    XCTAssertEqualObjects([self textFieldBoundTo:@"post" inView:editor.view].stringValue, @"Mars City");

    NSArray *emails = editor.emailArrayController.arrangedObjects;
    XCTAssertEqual(emails.count, 1U, @"the PDA references one email");
    XCTAssertEqualObjects([emails.firstObject valueForKey:@"subject"], @"Delta Labs");
    NSArray *audios = editor.audioArrayController.arrangedObjects;
    XCTAssertEqual(audios.count, 1U, @"the PDA references one audio log");
    XCTAssertEqualObjects([audios.firstObject valueForKey:@"audioName"], @"Shift Report");

    XCTAssertFalse(editor.editorDocument.isDocumentEdited, @"just opening the PDA must not dirty it");
}

- (void)testEditingAFieldDirtiesTheTabAndSaveWritesTheDeclFile {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDPDAEditorViewController *editor = [self openFixturePDAIn:controller];
    if (editor == nil) return;

    [self typeText:@"Ian B. McCormick" intoField:[self textFieldBoundTo:@"fullName" inView:editor.view]];
    [self typeText:@"EnPro Plant" intoField:[self textFieldBoundTo:@"post" inView:editor.view]];

    XCTAssertEqualObjects(editor.pda.fullName, @"Ian B. McCormick", @"typing should reach the model through the binding");
    XCTAssertEqualObjects(editor.pda.post, @"EnPro Plant");
    XCTAssertTrue(editor.editorDocument.isDocumentEdited, @"an edit should mark the tab dirty");

    [self save:controller];
    XCTAssertFalse(editor.editorDocument.isDocumentEdited, @"Save should leave the tab clean");

    NSString *text = [self savedPDAFileText];
    XCTAssertTrue([text containsString:@"Ian B. McCormick"], @"the saved file should have the new full name:\n%@", text);
    XCTAssertTrue([text containsString:@"EnPro Plant"], @"the saved file should have the new post:\n%@", text);
    XCTAssertFalse([text containsString:@"Ian A. McCormick"], @"the old full name should be gone:\n%@", text);
    XCTAssertTrue([text containsString:@"udtest_pda_email_1"], @"the untouched email must survive:\n%@", text);
    XCTAssertTrue([text containsString:@"Shift Report"], @"the untouched audio log must survive:\n%@", text);

    // A freshly opened workspace reads the edit back.
    [self closeWorkspace:controller];
    UDWorkspaceWindowController *reopened = [self openFixtureWorkspace];
    UDPDAEditorViewController *again = [self openFixturePDAIn:reopened];
    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:again.view].stringValue, @"Ian B. McCormick");
    XCTAssertEqualObjects(again.pda.post, @"EnPro Plant");
    XCTAssertEqual([again.emailArrayController.arrangedObjects count], 1U);
}

- (void)testUndoRevertsAFieldEdit {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDPDAEditorViewController *editor = [self openFixturePDAIn:controller];
    if (editor == nil) return;

    NSTextField *title = [self textFieldBoundTo:@"security" inView:editor.view];
    [self typeText:@"Level 3" intoField:title];
    XCTAssertEqualObjects(editor.pda.security, @"Level 3");

    NSUndoManager *undoManager = [controller.window undoManager];
    XCTAssertTrue(undoManager.canUndo, @"the edit should be undoable from the window");
    [editor.document.editingContext processPendingChanges];
    [undoManager undo];
    [self spinUntil:^BOOL{ return NO; } timeout:0.05];

    XCTAssertTrue(editor.pda.security.length == 0, @"Undo should restore the empty security level, not %@", editor.pda.security);
    XCTAssertEqualObjects(title.stringValue, @"", @"and the field should show it");
}

- (void)testRandButtonGeneratesAnIDNumber {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDPDAEditorViewController *editor = [self openFixturePDAIn:controller];
    if (editor == nil) return;

    NSButton *rand = [self buttonTitled:@"Rand" inView:editor.view];
    XCTAssertNotNil(rand, @"the PDA editor has a Rand button next to the ID Number");
    [rand performClick:nil];

    NSString *ident = editor.pda.ident;
    XCTAssertNotEqualObjects(ident, @"4122-36", @"Rand should replace the ID number");
    NSRegularExpression *shape = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{4}-[0-9A-F]{2}$" options:0 error:NULL];
    XCTAssertEqual([shape numberOfMatchesInString:ident options:0 range:NSMakeRange(0, ident.length)], 1U,
                   @"a generated ID looks like 1234-AB, not %@", ident);
    XCTAssertEqualObjects([self textFieldBoundTo:@"ident" inView:editor.view].stringValue, ident);
}

- (void)testAddingAnEmailThroughItsEditorSavesItWithThePDA {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDPDAEditorViewController *editor = [self openFixturePDAIn:controller];
    if (editor == nil) return;

    [self selectTabLabeled:@"Emails" inView:editor.view];
    NSSegmentedControl *emailButtons = [self segmentedControlWithAction:@selector(addOrRemoveEmail:) inView:editor.view];
    XCTAssertNotNil(emailButtons, @"the email list has +/- buttons");

    __block BOOL sawEditor = NO;
    [self whenModalWindowAppears:^(NSWindow *window) {
        sawEditor = YES;
        [self typeText:@"Sarge" intoField:[self textFieldBoundTo:@"from" inView:window.contentView]];
        [self typeText:@"Ian McCormick" intoField:[self textFieldBoundTo:@"to" inView:window.contentView]];
        [self typeText:@"11-15-2145" intoField:[self textFieldBoundTo:@"date" inView:window.contentView]];
        [self typeText:@"Orders" intoField:[self textFieldBoundTo:@"subject" inView:window.contentView]];
        // The body is typed and left in flight: OK has to commit it.
        [self typeText:@"Report to the hangar." intoTextView:[self firstSubviewOfClass:[NSTextView class] inView:window.contentView]];
        [[self buttonTitled:@"OK" inView:window.contentView] performClick:nil];
    }];
    [emailButtons setSelectedSegment:0];
    [NSApp sendAction:emailButtons.action to:emailButtons.target from:emailButtons];

    XCTAssertTrue(sawEditor, @"+ on the email list should open the email editor");
    NSArray *emails = editor.emailArrayController.arrangedObjects;
    XCTAssertEqual(emails.count, 2U, @"OK should add the new email to the PDA");
    UDDeclEmail *added = nil;
    for (UDDeclEmail *email in emails) {
        if ([email.subject isEqualToString:@"Orders"]) added = email;
    }
    XCTAssertNotNil(added, @"the new email should carry what was typed");
    XCTAssertEqualObjects(added.from, @"Sarge");
    XCTAssertEqualObjects(added.body, @"Report to the hangar.", @"OK should commit the body still being edited");
    XCTAssertTrue([added.name hasPrefix:@"udtest_pda_email_"], @"new emails are named after their PDA, not %@", added.name);
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);

    [self save:controller];
    NSString *text = [self savedPDAFileText];
    NSString *emailDecl = [NSString stringWithFormat:@"email %@", added.name];
    NSString *emailReference = [NSString stringWithFormat:@"\"%@\"", added.name];
    XCTAssertTrue([text containsString:emailDecl],
                  @"the new email decl should be written to the PDA's file:\n%@", text);
    XCTAssertTrue([text containsString:@"Orders"], @"%@", text);
    XCTAssertTrue([text containsString:@"Report to the hangar."], @"%@", text);
    XCTAssertTrue([text containsString:emailReference],
                  @"and the PDA should reference it:\n%@", text);

    NSString *addedName = added.name;
    [self closeWorkspace:controller];
    UDPDAEditorViewController *again = [self openFixturePDAIn:[self openFixtureWorkspace]];
    XCTAssertEqual([again.emailArrayController.arrangedObjects count], 2U, @"the reopened PDA should list both emails");
    XCTAssertTrue([[again.emailArrayController.arrangedObjects valueForKey:@"name"] containsObject:addedName]);
}

- (void)testCancellingTheEmailEditorAddsNothing {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDPDAEditorViewController *editor = [self openFixturePDAIn:controller];
    if (editor == nil) return;

    [self selectTabLabeled:@"Emails" inView:editor.view];
    NSSegmentedControl *emailButtons = [self segmentedControlWithAction:@selector(addOrRemoveEmail:) inView:editor.view];
    __block BOOL sawEditor = NO;
    [self whenModalWindowAppears:^(NSWindow *window) {
        sawEditor = YES;
        [self typeText:@"Never sent" intoField:[self textFieldBoundTo:@"subject" inView:window.contentView]];
        [[self buttonTitled:@"Cancel" inView:window.contentView] performClick:nil];
    }];
    [emailButtons setSelectedSegment:0];
    [NSApp sendAction:emailButtons.action to:emailButtons.target from:emailButtons];

    XCTAssertTrue(sawEditor, @"+ on the email list should open the email editor");
    XCTAssertEqual([editor.emailArrayController.arrangedObjects count], 1U, @"Cancel should add no email");
    NSUInteger inserted = [editor.document.editingContext.insertedObjects count];
    XCTAssertEqual(inserted, 0U, @"Cancel should also undo the new email decl itself");
}

- (void)testRemovingAnEmailDetachesItFromThePDA {
    UDWorkspaceWindowController *controller = [self openFixtureWorkspace];
    UDPDAEditorViewController *editor = [self openFixturePDAIn:controller];
    if (editor == nil) return;

    [self selectTabLabeled:@"Emails" inView:editor.view];
    NSSegmentedControl *emailButtons = [self segmentedControlWithAction:@selector(addOrRemoveEmail:) inView:editor.view];
    XCTAssertTrue([editor.emailArrayController setSelectionIndex:0], @"select the only email");
    [emailButtons setSelectedSegment:1];
    [NSApp sendAction:emailButtons.action to:emailButtons.target from:emailButtons];

    XCTAssertEqual([editor.emailArrayController.arrangedObjects count], 0U, @"- should take the email off the list");
    XCTAssertEqual(editor.pda.emails.count, 0U, @"and off the PDA");

    [self save:controller];
    NSString *text = [self savedPDAFileText];
    NSString *pdaDecl = [self declNamed:@"pda udtest_pda" inText:text];
    XCTAssertFalse([pdaDecl containsString:@"pda_email"], @"the PDA should no longer reference the email:\n%@", pdaDecl);
    XCTAssertTrue([pdaDecl containsString:@"pda_audio"], @"the audio log is untouched:\n%@", pdaDecl);
}

@end
