/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclCodecTests.m
 *
 * The table and skin codecs are ports of the engine's parsers
 * (idDeclTable::Parse, idDeclSkin::Parse): what they read from a decl's text
 * is what the engine reads, a broken decl included (the engine's default).
 */
#import <XCTest/XCTest.h>
#import "UDDeclManagedObjects.h"

@interface UDDeclCodecTests : XCTestCase
@end

@implementation UDDeclCodecTests

- (NSDictionary *)table:(NSString *)text {
    NSError *error = nil;
    NSDictionary *values = [UDDeclTable ud_parseValuesFromText:[text dataUsingEncoding:NSUTF8StringEncoding]
                                                           name:@"t" fileName:@"materials/t.mtr" lineNum:1
                                                     fileSystem:nil error:&error];
    XCTAssertNotNil(values, @"%@", error);
    return values;
}

- (NSDictionary *)skin:(NSString *)text {
    NSError *error = nil;
    NSDictionary *values = [UDDeclSkin ud_parseValuesFromText:[text dataUsingEncoding:NSUTF8StringEncoding]
                                                          name:@"s" fileName:@"skins/s.skin" lineNum:1
                                                    fileSystem:nil error:&error];
    XCTAssertNotNil(values, @"%@", error);
    return values;
}

- (void)testATablesValuesSnapAndClamp {
    NSDictionary *values = [self table:@"table t { snap clamp { 0, 0.5, -1, 1 } }"];
    XCTAssertEqualObjects(values[@"snap"], @YES);
    XCTAssertEqualObjects(values[@"clamp"], @YES);
    XCTAssertEqualObjects([values[@"values"] valueForKey:@"number"], (@[@0, @0.5, @-1, @1]));

    values = [self table:@"table t { { 1, 2 } }"];
    XCTAssertEqualObjects(values[@"snap"], @NO);
    XCTAssertEqualObjects([values[@"values"] valueForKey:@"number"], (@[@1, @2]));
}

/// What idDeclTable::Parse makes the default ({ { 0 } }), the codec does too.
/// The default, as the codec reads it: neither snap nor clamp, one value, 0.
- (void)assertDefault:(NSDictionary *)values because:(NSString *)because {
    XCTAssertEqualObjects(values[@"snap"], @NO, @"%@", because);
    XCTAssertEqualObjects(values[@"clamp"], @NO, @"%@", because);
    XCTAssertEqualObjects([values[@"values"] valueForKey:@"number"], @[@0], @"%@", because);
}

- (void)testABrokenTableIsTheDefault {
    [self assertDefault:[self table:@"table t { 1, 2, 3 }"] because:@"values outside an inner brace pair"];
    [self assertDefault:[self table:@"table t { { } }"] because:@"no values"];
    [self assertDefault:[self table:@"table t { { 1 2 } }"] because:@"no comma between values"];
    [self assertDefault:[self table:@"table t { snap { 1, x } }"] because:@"something non-numeric"];
}

- (void)testASkinsMappingsAndModels {
    NSDictionary *values = [self skin:
        @"skin s {\n"
         "\tmodel models/monsters/imp/imp.md5mesh\n"
         "\t* textures/common/nodraw\n"
         "\tmodels/monsters/imp/imp models/monsters/imp/imp_burnt\n"
         "}\n"];
    XCTAssertEqualObjects([values[@"associatedModels"] valueForKey:@"path"], @[@"models/monsters/imp/imp.md5mesh"]);
    XCTAssertEqualObjects([values[@"mappings"] valueForKey:@"from"], (@[@"*", @"models/monsters/imp/imp"]));
    XCTAssertEqualObjects([values[@"mappings"] valueForKey:@"to"],
                          (@[@"textures/common/nodraw", @"models/monsters/imp/imp_burnt"]));
}

/// A mapping cut short: idDeclSkin::Parse's MakeDefault().
- (void)testASkinCutShortIsTheDefault {
    NSDictionary *values = [self skin:@"skin s { textures/a"];
    XCTAssertEqualObjects([values[@"mappings"] valueForKey:@"from"], @[@"*"]);
    XCTAssertEqualObjects([values[@"mappings"] valueForKey:@"to"], @[@"_default"]);
    XCTAssertEqual([values[@"associatedModels"] count], 0U);
}

/// An element in its decl: setting one of its properties puts an edited
/// copy in its place, so the decl's setter runs (undo, the decl updated).
- (void)testAnElementsEditIsItsDecls {
    UDTableValue *loose = [UDTableValue valueWithNumber:1];
    loose.number = 2;
    XCTAssertEqual(loose.number, 2.0f, @"outside a decl it simply changes");

    UDSkinMapping *mapping = [UDSkinMapping mappingFrom:@"*" to:@"a"];
    id good = @" textures/b ", bad = @"two words";
    XCTAssertTrue([mapping validateValue:&good forKey:@"to" error:NULL]);
    XCTAssertEqualObjects(good, @"textures/b", @"trimmed");
    XCTAssertFalse([mapping validateValue:&bad forKey:@"to" error:NULL], @"a name with a space is refused");
}

@end
