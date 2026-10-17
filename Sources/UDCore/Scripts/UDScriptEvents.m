//
//  UDScriptEvents.m
//  UDCore
//

#import "UDScriptEvents.h"
#import "idParser.h"

@implementation UDScriptEvent

- (instancetype)initWithName:(NSString *)name parms:(NSString *)parms help:(NSString *)help {
    if (!(self = [super init])) return nil;
    _name = [name copy];
    _parms = [parms copy];
    _help = [help copy];
    return self;
}

@end

@implementation UDScriptEvents

- (instancetype)initWithEvents:(NSArray<UDScriptEvent *> *)events {
    if (!(self = [super init])) return nil;
    _events = [events copy];
    return self;
}

+ (instancetype)eventsFromFileSystem:(idFileSystem *)fileSystem {
    idParser *src = [[idParser alloc] initWithFlags:0 fileSystem:fileSystem];
    if (fileSystem == nil || ![src loadFile:@"script/doom_events.script" isOSPath:NO error:NULL]) {
        return [[self alloc] initWithEvents:@[]];
    }
    return [[self alloc] initWithEvents:[self eventsFromParser:src]];
}

+ (instancetype)eventsFromText:(NSString *)text {
    NSMutableData *bytes = [[text dataUsingEncoding:NSUTF8StringEncoding] mutableCopy] ?: [NSMutableData data];
    int length = (int)bytes.length;
    [bytes appendBytes:"" length:1];        // NUL-terminated, as idLexer expects
    idParser *src = [[idParser alloc] initWithFlags:0 fileSystem:nil];
    if (![src loadMemory:bytes.bytes length:length name:@"doom_events.script" error:NULL]) {
        return [[self alloc] initWithEvents:@[]];
    }
    return [[self alloc] initWithEvents:[self eventsFromParser:src]];
}

// InitScriptEvents
+ (NSArray<UDScriptEvent *> *)eventsFromParser:(idParser *)src {
    NSMutableArray<UDScriptEvent *> *events = [NSMutableArray array];
    NSMutableString *whiteSpace = [NSMutableString string];
    idToken token;
    idToken_Init(&token);

    while ([src readToken:&token error:NULL]) {
        if (strcmp(token.text, "scriptEvent") != 0) continue;

        NSString *help = @"";
        [src lastWhiteSpace:whiteSpace];
        NSRange comment = [whiteSpace rangeOfString:@"//"];
        if (comment.location != NSNotFound) {
            help = [[whiteSpace substringFromIndex:comment.location] stringByReplacingOccurrencesOfString:@"\r" withString:@""];
        }

        if (![src expectTokenType:TT_NAME subtype:0 token:&token error:NULL]) break;
        NSMutableString *parms = [NSMutableString stringWithUTF8String:token.text];

        if (![src expectTokenType:TT_NAME subtype:0 token:&token error:NULL]) break;
        NSString *name = [NSString stringWithUTF8String:token.text];

        if (![src expectTokenString:@"(" error:NULL]) break;

        [parms appendFormat:@" %@(", name];
        while ([src readToken:&token error:NULL] && strcmp(token.text, ";") != 0) {
            [parms appendFormat:@" %s", token.text];
        }

        [events addObject:[[UDScriptEvent alloc] initWithName:name parms:parms help:help]];
    }
    return events;
}

- (nullable UDScriptEvent *)eventNamed:(NSString *)name {
    for (UDScriptEvent *event in _events) {
        if ([event.name isEqualToString:name]) return event;
    }
    return nil;
}

// GetScriptEvents
- (NSArray<NSString *> *)membersOfObject:(NSString *)objectName {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UDScriptEvent *event in _events) [names addObject:event.name];
    return [names sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

// GetFunctionParms
- (nullable NSString *)functionParmsForName:(NSString *)name {
    return [self eventNamed:name].parms;
}

// GetToolTip
- (nullable NSString *)toolTipForName:(NSString *)name {
    UDScriptEvent *event = [self eventNamed:name];
    return event ? [event.help stringByAppendingString:event.parms] : nil;
}

@end
