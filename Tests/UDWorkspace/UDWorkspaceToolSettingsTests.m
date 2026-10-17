/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDWorkspaceToolSettingsTests.m — the tools' settings kept with the
 * workspace's.
 */

#import <XCTest/XCTest.h>
#import "UDWorkspace.h"

@interface UDWorkspaceToolSettingsTests : XCTestCase
@property (nonatomic) NSInteger posted;
@property (nonatomic, copy) NSString *postedTool;
@end

@implementation UDWorkspaceToolSettingsTests

- (void)settingsChanged:(NSNotification *)notification {
    self.posted++;
    self.postedTool = notification.userInfo[@"tool"];
}

- (void)testAToolsSettingsAreSavedWithTheWorkspace {
    UDWorkspace *workspace = [[UDWorkspace alloc] initWithDictionary:@{ @"fs_basepath": @"/games/doom3" } rootDirectory:@"/games/doom3"];
    XCTAssertNil([workspace settingsForTool:@"GUIEditor"]);
    XCTAssertNil(workspace.dictionaryRepresentation[@"tools"], @"none saved while there are none");

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged:)
                                                 name:UDWorkspaceToolSettingsDidChangeNotification object:workspace];
    [workspace setSettings:@{ @"gridVisible": @YES } forTool:@"GUIEditor"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    XCTAssertEqual(self.posted, 1, @"a change is told");
    XCTAssertEqualObjects(self.postedTool, @"GUIEditor");
    XCTAssertEqualObjects([workspace settingsForTool:@"GUIEditor"], (@{ @"gridVisible": @YES }));

    NSDictionary *saved = workspace.dictionaryRepresentation;
    XCTAssertEqualObjects(saved[@"tools"], (@{ @"GUIEditor": @{ @"gridVisible": @YES } }));
    XCTAssertTrue([NSJSONSerialization isValidJSONObject:saved], @"the document is JSON");

    UDWorkspace *reopened = [[UDWorkspace alloc] initWithDictionary:saved rootDirectory:@"/games/doom3"];
    XCTAssertEqualObjects([reopened settingsForTool:@"GUIEditor"], (@{ @"gridVisible": @YES }));
}

- (void)testTheSettingsSheetLeavesTheToolsSettings {
    UDWorkspace *workspace = [[UDWorkspace alloc] initWithDictionary:@{} rootDirectory:@""];
    // the sheet's scratch copy, made before the tool's settings changed
    NSDictionary *scratch = workspace.dictionaryRepresentation;
    [workspace setSettings:@{ @"gridSnap": @YES } forTool:@"GUIEditor"];
    [workspace applySettingsFromDictionary:scratch];
    XCTAssertEqualObjects([workspace settingsForTool:@"GUIEditor"], (@{ @"gridSnap": @YES }));
}

@end
