//
//  UDLanguageServer.m
//  UDCore
//

#import "UDLanguageServer.h"

@implementation UDLanguageServer {
    NSString *_name;
    NSMutableDictionary<NSString *, NSString *> *_openTexts;
}

- (instancetype)initWithName:(NSString *)name {
    if (!(self = [super init])) return nil;
    _name = [name copy];
    _openTexts = [NSMutableDictionary dictionary];
    _connection = [[UDJSONRPCConnection alloc] initWithTarget:self];
    [_connection setRequestAction:@selector(initialize:) forMethod:@"initialize"];
    [_connection setRequestAction:@selector(shutdown:) forMethod:@"shutdown"];
    [_connection setNotificationAction:@selector(exit:) forMethod:@"exit"];
    [_connection setNotificationAction:@selector(didOpen:) forMethod:@"textDocument/didOpen"];
    [_connection setNotificationAction:@selector(didChange:) forMethod:@"textDocument/didChange"];
    [_connection setNotificationAction:@selector(didClose:) forMethod:@"textDocument/didClose"];
    return self;
}

- (NSString *)openTextOfDocument:(NSString *)uri {
    return _openTexts[uri];
}

#pragma mark For subclasses

- (NSDictionary *)capabilities {
    return @{};
}

- (void)serverWillInitialize {
}

- (void)documentDidChange:(NSString *)uri {
}

- (NSString *)textOfDocument:(NSString *)uri {
    return _openTexts[uri];
}

- (NSString *)textOfPositionParams:(NSDictionary *)params uri:(NSString **)uri index:(NSUInteger *)index {
    NSString *document = params[@"textDocument"][@"uri"];
    if (![document isKindOfClass:[NSString class]]) return nil;
    NSString *text = [self textOfDocument:document];
    if (text == nil) return nil;
    NSUInteger at = [[self class] indexOfPosition:params[@"position"] inText:text];
    if (at == NSNotFound) return nil;
    *uri = document;
    *index = at;
    return text;
}

#pragma mark Lifecycle

- (id)initialize:(NSDictionary *)params {
    [self serverWillInitialize];
    NSMutableDictionary *capabilities = [[self capabilities] mutableCopy];
    capabilities[@"textDocumentSync"] = @1;                   // the full text on each change
    return @{ @"capabilities": capabilities, @"serverInfo": @{ @"name": _name } };
}

- (id)shutdown:(NSDictionary *)params {
    _shutDown = YES;
    return [NSNull null];
}

- (void)exit:(NSDictionary *)params {
    _exited = YES;
    [_connection stop];
}

#pragma mark Documents

- (void)didOpen:(NSDictionary *)params {
    NSString *uri = params[@"textDocument"][@"uri"], *text = params[@"textDocument"][@"text"];
    if (![uri isKindOfClass:[NSString class]] || ![text isKindOfClass:[NSString class]]) return;
    _openTexts[uri] = text;
    [self documentDidChange:uri];
}

- (void)didChange:(NSDictionary *)params {
    NSString *uri = params[@"textDocument"][@"uri"], *text = [params[@"contentChanges"] lastObject][@"text"];
    if (![uri isKindOfClass:[NSString class]] || ![text isKindOfClass:[NSString class]]) return;
    _openTexts[uri] = text;
    [self documentDidChange:uri];
}

- (void)didClose:(NSDictionary *)params {
    NSString *uri = params[@"textDocument"][@"uri"];
    if (![uri isKindOfClass:[NSString class]]) return;
    [_openTexts removeObjectForKey:uri];
    [self documentDidChange:uri];
}

#pragma mark Positions

+ (NSUInteger)indexOfPosition:(NSDictionary *)position inText:(NSString *)text {
    if (![position isKindOfClass:[NSDictionary class]]) return NSNotFound;
    NSInteger line = [position[@"line"] integerValue], character = [position[@"character"] integerValue];
    NSUInteger index = 0;
    for (NSInteger i = 0; i < line; i++) {
        NSRange newline = [text rangeOfString:@"\n" options:NSLiteralSearch range:NSMakeRange(index, text.length - index)];
        if (newline.location == NSNotFound) return NSNotFound;
        index = NSMaxRange(newline);
    }
    NSRange rest = [text rangeOfString:@"\n" options:NSLiteralSearch range:NSMakeRange(index, text.length - index)];
    NSUInteger lineEnd = rest.location == NSNotFound ? text.length : rest.location;
    return MIN(index + (NSUInteger)MAX(character, 0), lineEnd);
}

+ (NSDictionary *)locationWithURI:(NSString *)uri line:(NSInteger)line character:(NSInteger)character length:(NSInteger)length {
    return @{
        @"uri": uri,
        @"range": @{
            @"start": @{ @"line": @(line), @"character": @(character) },
            @"end": @{ @"line": @(line), @"character": @(character + length) },
        },
    };
}

@end
