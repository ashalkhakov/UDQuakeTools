#import <XCTest/XCTest.h>
#import "UDDeclTextChecker.h"

@interface UDDeclTextCheckerTests : XCTestCase
@end

@implementation UDDeclTextCheckerTests

- (NSArray<UDDeclTextProblem *> *)check:(NSString *)text {
    return [UDDeclTextChecker problemsInDeclText:text fileSystem:nil];
}

- (void)testAWellFormedDeclHasNoProblems {
    XCTAssertEqual([self check:@"{\n\tdiffusemap\ttextures/a_d\n}\n"].count, 0U, @"a body");
    XCTAssertEqual([self check:@"textures/a\n{\n\t{\n\t\tblend add\n\t}\n}"].count, 0U, @"name and body, nested stage");
    XCTAssertEqual([self check:@"pda p1 {\n\tname \"A // not a comment\"\n\t// a comment\n}"].count, 0U, @"type, name and body");
}

- (void)testAnUnclosedBraceIsReportedWhereItOpened {
    // The '}' on line 5 closes the stage opened on line 3, so the brace left
    // open is the decl's own, on line 1 (whatever the indentation suggests).
    NSArray<UDDeclTextProblem *> *problems = [self check:@"{\n\tdiffusemap a\n\t{\n\t\tblend add\n}\n"];
    XCTAssertEqual(problems.count, 1U, @"%@", problems);
    XCTAssertEqual(problems.firstObject.line, 1);
    XCTAssertTrue(problems.firstObject.isError);
}

- (void)testTextAfterTheClosingBraceIsReported {
    NSArray<UDDeclTextProblem *> *problems = [self check:@"{\n\ta b\n}\n}\nextra\n"];
    XCTAssertEqual(problems.count, 1U, @"reported once: %@", problems);
    XCTAssertEqual(problems.firstObject.line, 4);
}

- (void)testAMissingBraceOrNameIsReported {
    XCTAssertEqual([self check:@"textures/a\n"].firstObject.line, 1);
    XCTAssertTrue([[self check:@""].firstObject.message containsString:@"missing '{'"]);
    NSArray *tooMany = [self check:@"material textures/a extra {\n}"];
    XCTAssertEqual(tooMany.count, 1U, @"%@", tooMany);
}

- (void)testLexerErrorsComeWithTheirLine {
    // An unterminated quoted string, on line 3.
    NSArray<UDDeclTextProblem *> *problems = [self check:@"{\n\tname \"ok\"\n\tfullname \"never closed\n}\n"];
    XCTAssertGreaterThan(problems.count, 0U);
    BOOL onLine3 = NO;
    for (UDDeclTextProblem *problem in problems) {
        onLine3 = onLine3 || (problem.line >= 3 && problem.isError);
    }
    XCTAssertTrue(onLine3, @"%@", problems);
}

- (void)testItIsLinearInTheText {
    // A 200k-line decl checks in well under a second.
    NSMutableString *text = [NSMutableString stringWithString:@"{\n"];
    for (int i = 0; i < 200000; i++) {
        [text appendString:@"\tkey value\n"];
    }
    [text appendString:@"}\n"];
    NSDate *start = [NSDate date];
    XCTAssertEqual([self check:text].count, 0U);
    XCTAssertLessThan(-[start timeIntervalSinceNow], 1.0);
}

@end
