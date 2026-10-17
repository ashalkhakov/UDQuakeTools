#import <XCTest/XCTest.h>
#import "UDScriptEvents.h"

@interface UDScriptEventsTests : XCTestCase
@end

@implementation UDScriptEventsTests

static NSString * const UDEventsText =
    @"// Turns a lamp on.\n"
    @"scriptEvent\tvoid\tlightOn( entity lamp );\n"
    @"\n"
    @"// How bright a lamp is, scaled.\n"
    @"scriptEvent\tfloat\tgetBrightness( entity lamp, float scale );\n"
    @"scriptEvent\tvoid\tdim();\n";

- (void)testEachScriptEventIsReadWithItsParametersAndHelp {
    UDScriptEvents *events = [UDScriptEvents eventsFromText:UDEventsText];
    XCTAssertEqual(events.events.count, 3U);
    UDScriptEvent *brightness = events.events[1];
    XCTAssertEqualObjects(brightness.name, @"getBrightness");
    XCTAssertEqualObjects(brightness.parms, @"float getBrightness( entity lamp , float scale )");
    XCTAssertTrue([brightness.help hasPrefix:@"// How bright a lamp is, scaled."], @"%@", brightness.help);
    XCTAssertEqualObjects(events.events[2].help, @"", @"no comment, no help");
}

- (void)testMembersParametersAndToolTips {
    UDScriptEvents *events = [UDScriptEvents eventsFromText:UDEventsText];
    NSArray *members = @[@"dim", @"getBrightness", @"lightOn"];
    XCTAssertEqualObjects([events membersOfObject:@"$lamp_1"], members, @"every event, sorted");
    XCTAssertEqualObjects([events functionParmsForName:@"lightOn"], @"void lightOn( entity lamp )");
    XCTAssertNil([events functionParmsForName:@"unknown"]);
    NSString *tip = [events toolTipForName:@"lightOn"];
    XCTAssertTrue([tip hasPrefix:@"// Turns a lamp on."] && [tip hasSuffix:@"void lightOn( entity lamp )"], @"%@", tip);
}

- (void)testNoFileSystemMeansNoEvents {
    XCTAssertEqual([UDScriptEvents eventsFromFileSystem:nil].events.count, 0U);
}

@end
