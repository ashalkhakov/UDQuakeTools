//
//  UDScriptLanguageServerTests.m
//  UDQuakeToolsTests
//

#import <XCTest/XCTest.h>
#import "UDScriptLanguageServer.h"
#import "UDWorkspace.h"

@interface UDScriptLanguageServerTests : XCTestCase
@property (nonatomic, strong) UDScriptLanguageServer *server;
@property (nonatomic, assign) NSInteger nextID;
@property (nonatomic, copy) NSString *rootDir;
@property (nonatomic, strong) UDWorkspace *workspace;
@end

static NSString *const UDEventsText =
    @"// Waits a while.\n"
    @"scriptEvent void wait( float time );\n"
    @"scriptEvent void fadeTo( vector color, float alpha, float time );\n";

static NSString *const UDLanternText =
    @"object lantern {\n"                                 // 0
    @"    void swing( float angle );\n"                   // 1
    @"};\n"                                               // 2
    @"\n"                                                 // 3
    @"void lantern::swing( float angle ) {\n"             // 4
    @"    wait( angle );\n"                               // 5
    @"}\n"                                                // 6
    @"\n"                                                 // 7
    @"void lightAll() {\n"                                // 8
    @"    lantern::swing( 1 );\n"                         // 9
    @"    $lantern1.fad\n"                                // 10
    @"}\n";

@implementation UDScriptLanguageServerTests

- (void)tearDown {
    [self.workspace shutdown];
    if (self.rootDir) [[NSFileManager defaultManager] removeItemAtPath:self.rootDir error:NULL];
    [super tearDown];
}

- (id)request:(NSString *)method params:(NSDictionary *)params {
    NSDictionary *reply = [self.server.connection replyToMessage:@{ @"jsonrpc": @"2.0", @"id": @(++self.nextID),
                                                         @"method": method, @"params": params }];
    XCTAssertEqualObjects(reply[@"id"], @(self.nextID));
    XCTAssertNil(reply[@"error"], @"%@", reply[@"error"]);
    return reply[@"result"];
}

- (void)notify:(NSString *)method params:(NSDictionary *)params {
    NSDictionary *reply = [self.server.connection replyToMessage:@{ @"jsonrpc": @"2.0", @"method": method, @"params": params }];
    XCTAssertNil(reply);
}

- (void)open:(NSString *)path text:(NSString *)text {
    [self notify:@"textDocument/didOpen" params:@{ @"textDocument": @{
        @"uri": [UDScriptLanguageServer URIForPath:path], @"languageId": @"idscript", @"version": @1, @"text": text } }];
}

- (NSDictionary *)at:(NSString *)path line:(NSInteger)line character:(NSInteger)character {
    return @{ @"textDocument": @{ @"uri": [UDScriptLanguageServer URIForPath:path] },
              @"position": @{ @"line": @(line), @"character": @(character) } };
}

- (void)startWithOpenDocuments {
    self.server = [[UDScriptLanguageServer alloc] initWithFileSystem:nil];
    NSDictionary *result = [self request:@"initialize" params:@{}];
    XCTAssertEqualObjects(result[@"capabilities"][@"definitionProvider"], @YES);
    [self open:@"script/doom_events.script" text:UDEventsText];
    [self open:@"script/lantern.script" text:UDLanternText];
}

- (void)testADefinitionIsWhereItsNameIs {
    [self startWithOpenDocuments];

    // "swing" in "lantern::swing( 1 )": the method's definition, then its declaration.
    NSArray *locations = [self request:@"textDocument/definition" params:[self at:@"script/lantern.script" line:9 character:16]];
    XCTAssertEqual(locations.count, 2u);
    XCTAssertEqualObjects(locations[0][@"uri"], @"udfs:///script/lantern.script");
    XCTAssertEqualObjects(locations[0][@"range"][@"start"], (@{ @"line": @4, @"character": @14 }));
    XCTAssertEqualObjects(locations[0][@"range"][@"end"], (@{ @"line": @4, @"character": @19 }));
    XCTAssertEqualObjects(locations[1][@"range"][@"start"], (@{ @"line": @1, @"character": @9 }));

    // "lantern" in the same: the object.
    locations = [self request:@"textDocument/definition" params:[self at:@"script/lantern.script" line:9 character:6]];
    XCTAssertEqual(locations.count, 1u);
    XCTAssertEqualObjects(locations[0][@"range"][@"start"], (@{ @"line": @0, @"character": @7 }));

    // "wait": the event, in another script.
    locations = [self request:@"textDocument/definition" params:[self at:@"script/lantern.script" line:5 character:8]];
    XCTAssertEqualObjects(locations[0][@"uri"], @"udfs:///script/doom_events.script");
    XCTAssertEqualObjects(locations[0][@"range"][@"start"], (@{ @"line": @1, @"character": @17 }));

    // Nothing at a blank line.
    XCTAssertEqualObjects([self request:@"textDocument/definition" params:[self at:@"script/lantern.script" line:3 character:0]],
                          [NSNull null]);
}

- (void)testAnEditIsSeenAndClosingGoesBackToTheFileSystem {
    [self startWithOpenDocuments];
    NSString *uri = [UDScriptLanguageServer URIForPath:@"script/lantern.script"];
    [self notify:@"textDocument/didChange" params:@{ @"textDocument": @{ @"uri": uri, @"version": @2 },
                                                     @"contentChanges": @[ @{ @"text": @"\n\nfloat swing;\n" } ] }];
    [self open:@"script/other.script" text:@"swing\n"];
    NSArray *locations = [self request:@"textDocument/definition" params:[self at:@"script/other.script" line:0 character:2]];
    XCTAssertEqual(locations.count, 1u);
    XCTAssertEqualObjects(locations[0][@"range"][@"start"], (@{ @"line": @2, @"character": @6 }));

    // No file system: a closed script is gone.
    [self notify:@"textDocument/didClose" params:@{ @"textDocument": @{ @"uri": uri } }];
    XCTAssertEqual([[self request:@"textDocument/definition" params:[self at:@"script/other.script" line:0 character:2]] count], 0u);
}

- (void)testCompletionOffersEventsAfterADotAndDefinitionsOtherwise {
    [self startWithOpenDocuments];

    NSDictionary *result = [self request:@"textDocument/completion" params:[self at:@"script/lantern.script" line:10 character:17]];
    NSArray *labels = [result[@"items"] valueForKey:@"label"];
    XCTAssertEqualObjects(labels, (@[ @"fadeTo", @"wait" ]));
    XCTAssertEqualObjects(result[@"items"][0][@"detail"], @"void fadeTo( vector color , float alpha , float time )");
    XCTAssertEqualObjects(result[@"items"][0][@"insertText"], @"fadeTo(${1:vector color}, ${2:float alpha}, ${3:float time})",
                          @"a call, its parameters as tab stops");
    XCTAssertEqualObjects(result[@"items"][0][@"insertTextFormat"], @2);

    result = [self request:@"textDocument/completion" params:[self at:@"script/lantern.script" line:5 character:6]];
    labels = [result[@"items"] valueForKey:@"label"];
    XCTAssertTrue([labels containsObject:@"lightAll"]);
    NSDictionary *wait = [result[@"items"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"label == 'wait'"]].firstObject;
    XCTAssertEqualObjects(wait[@"insertText"], @"wait(${1:float time})", @"an event, called bare, with its parameters");
    NSDictionary *swing = [result[@"items"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"label == 'swing'"]].firstObject;
    XCTAssertEqualObjects(swing[@"insertText"], @"swing(${1:float angle})", @"a method, with its parameters");
    XCTAssertTrue([labels containsObject:@"lantern"]);
    XCTAssertEqual([[[NSCountedSet alloc] initWithArray:labels] countForObject:@"swing"], 1u);
}

- (void)testHoverShowsAnEventsHelpOrADeclaration {
    [self startWithOpenDocuments];

    NSDictionary *hover = [self request:@"textDocument/hover" params:[self at:@"script/lantern.script" line:5 character:5]];
    XCTAssertTrue([hover[@"contents"][@"value"] containsString:@"Waits a while."], @"%@", hover);
    XCTAssertTrue([hover[@"contents"][@"value"] containsString:@"void wait( float time )"], @"%@", hover);

    // "void": nothing to say.
    XCTAssertEqualObjects([self request:@"textDocument/hover" params:[self at:@"script/lantern.script" line:8 character:1]],
                          [NSNull null]);

    hover = [self request:@"textDocument/hover" params:[self at:@"script/lantern.script" line:9 character:16]];
    XCTAssertEqualObjects(hover[@"contents"][@"value"], @"void lantern::swing( float angle ) {\n\nscript/lantern.script:5");
}

- (void)testAnEventsParametersShowInsideItsCall {
    [self startWithOpenDocuments];
    [self open:@"script/call.script" text:@"void f() { wait( 1 + ( 2 ), \n"];

    NSDictionary *help = [self request:@"textDocument/signatureHelp" params:[self at:@"script/call.script" line:0 character:28]];
    XCTAssertEqualObjects(help[@"signatures"][0][@"label"], @"void wait( float time )");
    XCTAssertEqualObjects([self request:@"textDocument/signatureHelp" params:[self at:@"script/call.script" line:0 character:8]],
                          [NSNull null], @"not inside a call");
    XCTAssertEqualObjects([self request:@"textDocument/signatureHelp" params:[self at:@"script/call.script" line:0 character:7]],
                          [NSNull null], @"f is no event");
}

- (void)testScriptsComeFromTheFileSystemAndItsChanges {
    self.rootDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *scripts = [self.rootDir stringByAppendingPathComponent:@"base/script"];
    [[NSFileManager defaultManager] createDirectoryAtPath:scripts withIntermediateDirectories:YES attributes:nil error:NULL];
    [UDEventsText writeToFile:[scripts stringByAppendingPathComponent:@"doom_events.script"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [UDLanternText writeToFile:[scripts stringByAppendingPathComponent:@"lantern.script"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    self.workspace = [[UDWorkspace alloc] initWithDictionary:@{ @"fs_basepath": self.rootDir, @"fs_savepath": self.rootDir,
                                                                @"fs_cdpath": self.rootDir, @"fs_game": @"base" }
                                               rootDirectory:self.rootDir];
    XCTAssertTrue([self.workspace startup:NULL]);
    self.server = [[UDScriptLanguageServer alloc] initWithFileSystem:self.workspace.fileSystem];
    [self request:@"initialize" params:@{}];

    [self open:@"script/main.script" text:@"lightAll\n"];
    NSArray *locations = [self request:@"textDocument/definition" params:[self at:@"script/main.script" line:0 character:0]];
    XCTAssertEqual(locations.count, 1u);
    XCTAssertEqualObjects(locations[0][@"uri"], @"udfs:///script/lantern.script");
    XCTAssertEqualObjects(locations[0][@"range"][@"start"], (@{ @"line": @8, @"character": @5 }));

    NSDictionary *hover = [self request:@"textDocument/hover" params:[self at:@"script/lantern.script" line:5 character:5]];
    XCTAssertTrue([hover[@"contents"][@"value"] containsString:@"Waits a while."], @"%@", hover);

    // The workspace writes lantern.script: lightAll moves.
    [[@"\n" stringByAppendingString:UDLanternText] writeToFile:[scripts stringByAppendingPathComponent:@"lantern.script"]
                                                    atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [self notify:@"workspace/didChangeWatchedFiles" params:@{ @"changes": @[
        @{ @"uri": [UDScriptLanguageServer URIForPath:@"script/lantern.script"], @"type": @2 } ] }];
    locations = [self request:@"textDocument/definition" params:[self at:@"script/main.script" line:0 character:0]];
    XCTAssertEqualObjects(locations[0][@"range"][@"start"], (@{ @"line": @9, @"character": @5 }));
}

- (void)testShutdownThenExit {
    self.server = [[UDScriptLanguageServer alloc] initWithFileSystem:nil];
    XCTAssertEqualObjects([self request:@"shutdown" params:@{}], [NSNull null]);
    XCTAssertTrue(self.server.shutDown);
    [self notify:@"exit" params:@{}];
    XCTAssertTrue(self.server.exited);

    NSDictionary *reply = [self.server.connection replyToMessage:@{ @"jsonrpc": @"2.0", @"id": @7, @"method": @"textDocument/rename" }];
    XCTAssertEqualObjects(reply[@"error"][@"code"], @(-32601));
}

- (void)testAPathIsAUDFSURI {
    XCTAssertEqualObjects([UDScriptLanguageServer URIForPath:@"script/my lamp.script"], @"udfs:///script/my%20lamp.script");
    XCTAssertEqualObjects([UDScriptLanguageServer pathForURI:@"udfs:///script/my%20lamp.script"], @"script/my lamp.script");
    XCTAssertNil([UDScriptLanguageServer pathForURI:@"file:///tmp/x.script"]);
}

@end
