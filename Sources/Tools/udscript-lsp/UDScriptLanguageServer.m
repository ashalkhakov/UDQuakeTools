//
//  UDScriptLanguageServer.m
//  udscript-lsp
//

#import "UDScriptLanguageServer.h"
#import "UDScriptIndex.h"
#import "UDScriptEvents.h"
#import "idFileSystem.h"

static NSString *const UDEventsPath = @"script/doom_events.script";

// LSP's CompletionItemKind
enum { UDCompletionMethod = 2, UDCompletionFunction = 3, UDCompletionField = 5, UDCompletionVariable = 6,
       UDCompletionClass = 7, UDCompletionModule = 9, UDCompletionEvent = 23 };

@implementation UDScriptLanguageServer {
    idFileSystem *_fileSystem;
    UDScriptIndex *_index;
    UDScriptEvents *_events;
}

- (instancetype)initWithFileSystem:(idFileSystem *)fileSystem {
    if (!(self = [super initWithName:@"udscript-lsp"])) return nil;
    _fileSystem = fileSystem;
    _index = [[UDScriptIndex alloc] init];
    _events = [UDScriptEvents eventsFromText:@""];
    [self.connection setRequestAction:@selector(definition:) forMethod:@"textDocument/definition"];
    [self.connection setRequestAction:@selector(completion:) forMethod:@"textDocument/completion"];
    [self.connection setRequestAction:@selector(hover:) forMethod:@"textDocument/hover"];
    [self.connection setRequestAction:@selector(signatureHelp:) forMethod:@"textDocument/signatureHelp"];
    [self.connection setNotificationAction:@selector(didChangeWatchedFiles:) forMethod:@"workspace/didChangeWatchedFiles"];
    return self;
}

#pragma mark - URIs

+ (NSString *)URIForPath:(NSString *)path {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"udfs";
    components.host = @"";
    components.path = [@"/" stringByAppendingString:path];
    return components.string;
}

+ (NSString *)pathForURI:(NSString *)uri {
    NSURLComponents *components = [NSURLComponents componentsWithString:uri];
    if (![components.scheme isEqualToString:@"udfs"]) return nil;
    NSString *path = components.path;
    while ([path hasPrefix:@"/"]) path = [path substringFromIndex:1];
    return path.length > 0 ? path : nil;
}

#pragma mark - Texts

/// A script in the file system, or nil.
- (NSString *)fileSystemTextOfPath:(NSString *)path {
    if (_fileSystem == nil) return nil;
    void *buffer = NULL;
    int length = [_fileSystem readFile:path buffer:&buffer timestamp:NULL error:NULL];
    if (length < 0 || buffer == NULL) return nil;
    NSData *data = [NSData dataWithBytes:buffer length:(NSUInteger)length];
    [_fileSystem freeFile:buffer error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

/// A script as it is now: as open, or in the file system.
- (NSString *)textOfPath:(NSString *)path {
    return [self openTextOfDocument:[[self class] URIForPath:path]] ?: [self fileSystemTextOfPath:path];
}

- (NSString *)textOfDocument:(NSString *)uri {
    NSString *path = [[self class] pathForURI:uri];
    return path ? [self textOfPath:path] : nil;
}

/// Reads @a path again, after it was opened, edited, closed or changed.
- (void)reindexPath:(NSString *)path {
    NSString *text = [self textOfPath:path];
    if (text != nil) {
        [_index setText:text forPath:path];
    } else {
        [_index removePath:path];
    }
    if ([path caseInsensitiveCompare:UDEventsPath] == NSOrderedSame) {
        _events = [UDScriptEvents eventsFromText:text ?: @""];
    }
}

#pragma mark - UDLanguageServer

- (NSDictionary *)capabilities {
    return @{
        @"definitionProvider": @YES,
        @"hoverProvider": @YES,
        @"completionProvider": @{ @"triggerCharacters": @[ @"." ] },
        @"signatureHelpProvider": @{ @"triggerCharacters": @[ @"(" ], @"retriggerCharacters": @[ @"," ] },
    };
}

/// Every script under script/ and maps/.
- (void)serverWillInitialize {
    if (_fileSystem == nil) return;
    for (NSString *directory in @[ @"script", @"maps" ]) {
        idFileList *files = [_fileSystem listFilesTree:directory extension:@".script" sorted:YES inGameDir:@"" error:NULL];
        for (NSString *path in files.list) {
            [self reindexPath:path];
        }
        [_fileSystem freeFileList:files];
    }
}

- (void)documentDidChange:(NSString *)uri {
    NSString *path = [[self class] pathForURI:uri];
    if (path != nil) [self reindexPath:path];
}

- (void)didChangeWatchedFiles:(NSDictionary *)params {
    for (NSDictionary *change in params[@"changes"]) {
        NSString *path = [[self class] pathForURI:change[@"uri"] ?: @""];
        if (path != nil && [path.pathExtension caseInsensitiveCompare:@"script"] == NSOrderedSame) {
            [self reindexPath:path];
        }
    }
}

#pragma mark - Names

static BOOL UDIsNameCharacter(unichar c) {
    return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

/// The name at @a index (the cursor on or just after it), with the scopes
/// written before it: "lamp::flicker" on "flicker". Nil when there is none.
static NSString *UDNameAtIndex(NSString *text, NSUInteger index) {
    NSUInteger from = index, to = index;
    while (from > 0 && UDIsNameCharacter([text characterAtIndex:from - 1])) from--;
    while (to < text.length && UDIsNameCharacter([text characterAtIndex:to])) to++;
    if (from == to) return nil;
    NSUInteger qualified = from;
    while (qualified >= 3 && [text characterAtIndex:qualified - 1] == ':' && [text characterAtIndex:qualified - 2] == ':'
           && UDIsNameCharacter([text characterAtIndex:qualified - 3])) {
        qualified -= 2;
        while (qualified > 0 && UDIsNameCharacter([text characterAtIndex:qualified - 1])) qualified--;
    }
    return [text substringWithRange:NSMakeRange(qualified, to - qualified)];
}

/// What @a name names, as seen from @a path: its definitions in that
/// script, if it has any; otherwise everywhere.
- (NSArray<UDScriptDefinition *> *)definitionsOfName:(NSString *)name fromPath:(NSString *)path {
    NSArray<UDScriptDefinition *> *all = [_index definitionsOfName:name];
    NSMutableArray<UDScriptDefinition *> *here = [NSMutableArray array];
    for (UDScriptDefinition *definition in all) {
        if ([definition.path isEqualToString:path]) [here addObject:definition];
    }
    return here.count > 0 ? here : all;
}

#pragma mark - Requests

- (id)definition:(NSDictionary *)params {
    NSString *uri = nil;
    NSUInteger index = 0;
    NSString *text = [self textOfPositionParams:params uri:&uri index:&index];
    NSString *name = text ? UDNameAtIndex(text, index) : nil;
    if (name == nil) return [NSNull null];
    NSMutableArray *locations = [NSMutableArray array];
    for (UDScriptDefinition *definition in [self definitionsOfName:name fromPath:[[self class] pathForURI:uri]]) {
        [locations addObject:[[self class] locationWithURI:[[self class] URIForPath:definition.path]
                                                      line:definition.line character:definition.column
                                                    length:definition.length]];
    }
    return locations;
}

static NSInteger UDCompletionKind(UDScriptDefinitionKind kind) {
    switch (kind) {
        case UDScriptDefinitionFunction:
        case UDScriptDefinitionFunctionPrototype: return UDCompletionFunction;
        case UDScriptDefinitionObject: return UDCompletionClass;
        case UDScriptDefinitionMethod:
        case UDScriptDefinitionMethodPrototype: return UDCompletionMethod;
        case UDScriptDefinitionField: return UDCompletionField;
        case UDScriptDefinitionEvent: return UDCompletionEvent;
        case UDScriptDefinitionNamespace: return UDCompletionModule;
        case UDScriptDefinitionVariable: return UDCompletionVariable;
    }
    return UDCompletionVariable;
}

/// A call of @a name with its parameters as tab stops, in LSP's snippet
/// syntax: "accelSound(${1:string sound})" for "void accelSound( string sound )".
static NSString *UDCallSnippet(NSString *name, NSString *parms) {
    NSRange open = [parms rangeOfString:@"("], close = [parms rangeOfString:@")" options:NSBackwardsSearch];
    NSMutableArray<NSString *> *stops = [NSMutableArray array];
    if (open.location != NSNotFound && close.location != NSNotFound && close.location > open.location) {
        NSString *list = [parms substringWithRange:NSMakeRange(NSMaxRange(open), close.location - NSMaxRange(open))];
        for (NSString *parm in [list componentsSeparatedByString:@","]) {
            NSString *trimmed = [parm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length == 0) continue;
            NSString *escaped = [[[trimmed stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                                  stringByReplacingOccurrencesOfString:@"$" withString:@"\\$"]
                                 stringByReplacingOccurrencesOfString:@"}" withString:@"\\}"];
            [stops addObject:[NSString stringWithFormat:@"${%lu:%@}", (unsigned long)stops.count + 1, escaped]];
        }
    }
    return [NSString stringWithFormat:@"%@(%@)", name, [stops componentsJoinedByString:@", "]];
}

/// Whether @a index is in a string or a "//" comment on its line: no names
/// are offered there.
static BOOL UDIndexIsInStringOrComment(NSString *text, NSUInteger index) {
    NSUInteger lineStart = [text lineRangeForRange:NSMakeRange(index, 0)].location;
    BOOL inString = NO;
    for (NSUInteger i = lineStart; i < index; i++) {
        unichar c = [text characterAtIndex:i];
        if (inString) {
            if (c == '\\') i++;
            else if (c == '"') inString = NO;
        } else if (c == '"') {
            inString = YES;
        } else if (c == '/' && i + 1 < index && [text characterAtIndex:i + 1] == '/') {
            return YES;
        }
    }
    return inString;
}

- (id)completion:(NSDictionary *)params {
    NSString *uri = nil;
    NSUInteger index = 0;
    NSString *text = [self textOfPositionParams:params uri:&uri index:&index];
    if (text == nil) return [NSNull null];
    if (UDIndexIsInStringOrComment(text, index)) return @{ @"isIncomplete": @NO, @"items": @[] };
    NSUInteger start = index;
    while (start > 0 && UDIsNameCharacter([text characterAtIndex:start - 1])) start--;

    NSMutableArray *items = [NSMutableArray array];
    if (start > 0 && [text characterAtIndex:start - 1] == '.') {         // <object>.<event>
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (NSString *name in [_events membersOfObject:@""]) {
            if ([seen containsObject:name]) continue;           // an event of sys's and of a thread's
            [seen addObject:name];
            NSString *parms = [_events functionParmsForName:name] ?: @"";
            [items addObject:@{ @"label": name, @"kind": @(UDCompletionEvent), @"detail": parms,
                                @"insertText": UDCallSnippet(name, parms), @"insertTextFormat": @2 }];
        }
    } else {
        // The scripts' names, and the events, which an object's methods call
        // bare (weaponState( "Reload", 1 )): calls with their parameters.
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (UDScriptDefinition *definition in _index.allDefinitions) {
            if ([seen containsObject:definition.name]) continue;
            [seen addObject:definition.name];
            NSMutableDictionary *item = [@{ @"label": definition.name, @"kind": @(UDCompletionKind(definition.kind)) } mutableCopy];
            NSString *eventParms = definition.kind == UDScriptDefinitionEvent ? [_events functionParmsForName:definition.name] : nil;
            if (eventParms != nil || definition.parameters != nil) {
                item[@"insertText"] = eventParms ? UDCallSnippet(definition.name, eventParms)
                    : UDCallSnippet(definition.name, [NSString stringWithFormat:@"(%@)", definition.parameters]);
                item[@"insertTextFormat"] = @2;
            }
            [items addObject:item];
        }
        for (NSString *name in [_events membersOfObject:@""]) {
            if ([seen containsObject:name]) continue;
            [seen addObject:name];
            NSString *parms = [_events functionParmsForName:name] ?: @"";
            [items addObject:@{ @"label": name, @"kind": @(UDCompletionEvent), @"detail": parms,
                                @"insertText": UDCallSnippet(name, parms), @"insertTextFormat": @2 }];
        }
    }
    return @{ @"isIncomplete": @NO, @"items": items };
}

- (id)hover:(NSDictionary *)params {
    NSString *uri = nil;
    NSUInteger index = 0;
    NSString *text = [self textOfPositionParams:params uri:&uri index:&index];
    NSString *name = text ? UDNameAtIndex(text, index) : nil;
    if (name == nil) return [NSNull null];

    NSString *value = [_events toolTipForName:name];
    if (value == nil) {
        UDScriptDefinition *definition = [self definitionsOfName:name fromPath:[[self class] pathForURI:uri]].firstObject;
        if (definition == nil) return [NSNull null];
        NSArray<NSString *> *lines = [[self textOfPath:definition.path] componentsSeparatedByString:@"\n"];
        if (definition.line >= (NSInteger)lines.count) return [NSNull null];
        NSString *declaration = [lines[(NSUInteger)definition.line]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        value = [NSString stringWithFormat:@"%@\n\n%@:%ld", declaration, definition.path, (long)definition.line + 1];
    }
    return @{ @"contents": @{ @"kind": @"plaintext", @"value": value } };
}

/// An event's parameters, inside its call's parentheses (GetFunctionParms):
/// the name before the '(' the cursor is in, when it is an event's.
- (id)signatureHelp:(NSDictionary *)params {
    NSString *uri = nil;
    NSUInteger index = 0;
    NSString *text = [self textOfPositionParams:params uri:&uri index:&index];
    if (text == nil) return [NSNull null];

    NSUInteger open = index;
    NSInteger depth = 0;
    while (open > 0) {
        unichar c = [text characterAtIndex:--open];
        if (c == ')') depth++;
        else if (c == '(' && depth-- == 0) break;
        else if (c == ';' || c == '{' || c == '}') return [NSNull null];
        if (open == 0) return [NSNull null];
    }
    if (index == 0 || [text characterAtIndex:open] != '(') return [NSNull null];
    NSUInteger start = open;
    while (start > 0 && [text characterAtIndex:start - 1] == ' ') start--;
    NSUInteger end = start;
    while (start > 0 && UDIsNameCharacter([text characterAtIndex:start - 1])) start--;
    NSString *parms = [_events functionParmsForName:[text substringWithRange:NSMakeRange(start, end - start)]];
    if (parms == nil) return [NSNull null];
    return @{ @"signatures": @[ @{ @"label": parms } ], @"activeSignature": @0 };
}

@end
