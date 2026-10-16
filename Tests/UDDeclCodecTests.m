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
    XCTAssertEqualObjects(values[@"values"], @"0, 0.5, -1, 1");

    values = [self table:@"table t { { 1, 2 } }"];
    XCTAssertEqualObjects(values[@"snap"], @NO);
    XCTAssertEqualObjects(values[@"values"], @"1, 2");
}

/// What idDeclTable::Parse makes the default ({ { 0 } }), the codec does too.
- (void)testABrokenTableIsTheDefault {
    NSDictionary *byDefault = @{ @"snap": @NO, @"clamp": @NO, @"values": @"0" };
    XCTAssertEqualObjects([self table:@"table t { 1, 2, 3 }"], byDefault, @"values outside an inner brace pair");
    XCTAssertEqualObjects([self table:@"table t { { } }"], byDefault, @"no values");
    XCTAssertEqualObjects([self table:@"table t { { 1 2 } }"], byDefault, @"no comma between values");
    XCTAssertEqualObjects([self table:@"table t { snap { 1, x } }"], byDefault, @"something non-numeric");
}

- (void)testASkinsMappingsAndModels {
    NSDictionary *values = [self skin:
        @"skin s {\n"
         "\tmodel models/monsters/imp/imp.md5mesh\n"
         "\t* textures/common/nodraw\n"
         "\tmodels/monsters/imp/imp models/monsters/imp/imp_burnt\n"
         "}\n"];
    XCTAssertEqualObjects(values[@"associatedModels"], @"models/monsters/imp/imp.md5mesh");
    XCTAssertEqualObjects(values[@"mappings"],
                          @"* textures/common/nodraw\nmodels/monsters/imp/imp models/monsters/imp/imp_burnt");
}

/// A mapping cut short: idDeclSkin::Parse's MakeDefault().
- (void)testASkinCutShortIsTheDefault {
    NSDictionary *values = [self skin:@"skin s { textures/a"];
    XCTAssertEqualObjects(values[@"mappings"], @"* _default");
    XCTAssertEqualObjects(values[@"associatedModels"], @"");
}

@end
