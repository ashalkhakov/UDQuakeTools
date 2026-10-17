//
//  UDScriptIndexTests.m
//  UDQuakeToolsTests
//

#import <XCTest/XCTest.h>
#import "UDScriptIndex.h"

@interface UDScriptIndexTests : XCTestCase
@end

static NSString *const UDLampScript =
    @"#include \"script/lamp_defs.script\"\n"                   // 0
    @"#define LAMP_GLOW 0.5\n"                                  // 1
    @"\n"                                                       // 2
    @"scriptEvent void glowTo( float level, float time );\n"    // 3
    @"float lampCount = 0, lampsLit;\n"                         // 4
    @"vector lampColor = '1 0.8 0.6';\n"                        // 5
    @"void blink();\n"                                          // 6
    @"\n"                                                       // 7
    @"object lamp : light_base {\n"                             // 8
    @"    float brightness;\n"                                  // 9
    @"    void flicker( float times );\n"                       // 10
    @"    void dim() { brightness = brightness * 0.5; }\n"      // 11
    @"};\n"                                                     // 12
    @"\n"                                                       // 13
    @"void lamp::flicker( float times ) {\n"                    // 14
    @"    while( times > 0 ) { times--; if ( times ) { dim(); } }\n"
    @"}\n"                                                      // 16
    @"\n"                                                       // 17
    @"namespace lamps {\n"                                      // 18
    @"    void glow( entity e ) { e.glowTo( LAMP_GLOW, 1 ); }\n"
    @"}\n"                                                      // 20
    @"\n"                                                       // 21
    @"void blink() {\n"                                         // 22
    @"\tlampCount = lampCount + 1; // éclat\n"             // 23
    @"}\n";

@implementation UDScriptIndexTests

- (UDScriptDefinition *)onlyDefinitionOf:(NSString *)name in:(UDScriptIndex *)index {
    NSArray<UDScriptDefinition *> *found = [index definitionsOfName:name];
    XCTAssertGreaterThan(found.count, 0u, @"%@", name);
    return found.firstObject;
}

- (void)testAScriptsDefinitionsAreFoundWhereTheyAre {
    UDScriptIndex *index = [[UDScriptIndex alloc] init];
    [index setText:UDLampScript forPath:@"script/lamp.script"];

    UDScriptDefinition *event = [self onlyDefinitionOf:@"glowTo" in:index];
    XCTAssertEqual(event.kind, UDScriptDefinitionEvent);
    XCTAssertEqual(event.line, 3);
    XCTAssertEqual(event.column, 17);
    XCTAssertEqual(event.length, 6);
    XCTAssertEqualObjects(event.path, @"script/lamp.script");

    XCTAssertEqual([self onlyDefinitionOf:@"lampCount" in:index].kind, UDScriptDefinitionVariable);
    XCTAssertEqual([self onlyDefinitionOf:@"lampsLit" in:index].column, 21);
    XCTAssertEqual([self onlyDefinitionOf:@"lampColor" in:index].line, 5);

    UDScriptDefinition *object = [self onlyDefinitionOf:@"lamp" in:index];
    XCTAssertEqual(object.kind, UDScriptDefinitionObject);
    XCTAssertEqual(object.line, 8);
    XCTAssertEqual(object.column, 7);

    XCTAssertEqual([self onlyDefinitionOf:@"lamp::brightness" in:index].kind, UDScriptDefinitionField);
    XCTAssertEqual([self onlyDefinitionOf:@"lamp::dim" in:index].kind, UDScriptDefinitionMethod);
    XCTAssertEqualObjects([self onlyDefinitionOf:@"lamp::dim" in:index].parameters, @"");
    XCTAssertEqualObjects([index definitionsOfName:@"lamp::flicker"].firstObject.parameters, @"float times",
                          @"a method's parameters, kept from its declaration to its definition");
    XCTAssertEqualObjects([self onlyDefinitionOf:@"lamps::glow" in:index].parameters, @"entity e");
    XCTAssertNil([self onlyDefinitionOf:@"lampCount" in:index].parameters, @"a variable has none");

    UDScriptDefinition *glow = [self onlyDefinitionOf:@"lamps::glow" in:index];
    XCTAssertEqual(glow.kind, UDScriptDefinitionFunction);
    XCTAssertEqual(glow.line, 19);
    XCTAssertEqual([self onlyDefinitionOf:@"lamps" in:index].kind, UDScriptDefinitionNamespace);

    // Nothing in a body, nor in the preprocessor's lines, is a definition.
    XCTAssertEqual([index definitionsOfName:@"times"].count, 0u);
    XCTAssertEqual([index definitionsOfName:@"LAMP_GLOW"].count, 0u);
    XCTAssertEqual([index definitionsOfName:@"e"].count, 0u);
    XCTAssertEqual([index definitionsOfName:@"light_base"].count, 0u);
}

- (void)testADefinitionComesBeforeItsPrototype {
    UDScriptIndex *index = [[UDScriptIndex alloc] init];
    [index setText:UDLampScript forPath:@"script/lamp.script"];

    NSArray<UDScriptDefinition *> *flicker = [index definitionsOfName:@"lamp::flicker"];
    XCTAssertEqual(flicker.count, 2u);
    XCTAssertEqual(flicker[0].kind, UDScriptDefinitionMethod);
    XCTAssertEqual(flicker[0].line, 14);
    XCTAssertEqual(flicker[0].column, 11);
    XCTAssertEqual(flicker[1].kind, UDScriptDefinitionMethodPrototype);
    XCTAssertEqual(flicker[1].line, 10);

    NSArray<UDScriptDefinition *> *blink = [index definitionsOfName:@"blink"];
    XCTAssertEqual(blink.count, 2u);
    XCTAssertEqual(blink[0].kind, UDScriptDefinitionFunction);
    XCTAssertEqual(blink[0].line, 22);
    XCTAssertEqual(blink[1].kind, UDScriptDefinitionFunctionPrototype);
}

- (void)testABareNameIsLookedUpInEveryScope {
    UDScriptIndex *index = [[UDScriptIndex alloc] init];
    [index setText:UDLampScript forPath:@"script/lamp.script"];
    [index setText:@"object torch {\n\tvoid flicker();\n};\n" forPath:@"script/torch.script"];

    NSArray<UDScriptDefinition *> *flicker = [index definitionsOfName:@"flicker"];
    XCTAssertEqual(flicker.count, 3u);
    XCTAssertEqualObjects(flicker[0].qualifiedName, @"lamp::flicker");
    XCTAssertEqual([index definitionsOfName:@"torch::flicker"].count, 1u);
}

- (void)testAScriptsTextReplacesItsDefinitions {
    UDScriptIndex *index = [[UDScriptIndex alloc] init];
    [index setText:@"void a() {}\n" forPath:@"script/x.script"];
    [index setText:@"\nvoid b() {}\n" forPath:@"script/x.script"];
    XCTAssertEqual([index definitionsOfName:@"a"].count, 0u);
    XCTAssertEqual([index definitionsOfName:@"b"].firstObject.line, 1);

    [index removePath:@"script/x.script"];
    XCTAssertFalse([index hasPath:@"script/x.script"]);
    XCTAssertEqual(index.allDefinitions.count, 0u);
}

- (void)testAColumnCountsUTF16Units {
    NSArray<UDScriptDefinition *> *found =
        [UDScriptIndex definitionsInText:@"/* é\U0001F4A1 */ float glow;\n" path:@"script/u.script"];
    XCTAssertEqual(found.count, 1u);
    XCTAssertEqual(found.firstObject.column, 16);
}

@end
