//
//  UDScriptLanguageServer.m
//  UDCore
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
    NSMutableDictionary<NSString *, NSString *> *_openTexts;
}

- (instancetype)initWithFileSystem:(idFileSystem *)fileSystem {
    if (!(self = [super init])) return nil;
    _fileSystem = fileSystem;
    _index = [[UDScriptIndex alloc] init];
    _events = [UDScriptEvents eventsFromText:@""];
    _openTexts = [NSMutableDictionary dictionary];
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
    return _openTexts[path] ?: [self fileSystemTextOfPath:path];
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

- (void)indexFileSystem {
    if (_fileSystem == nil) return;
    for (NSString *directory in @[ @"script", @"maps" ]) {
        idFileList *files = [_fileSystem listFilesTree:directory extension:@".script" sorted:YES inGameDir:@"" error:NULL];
        for (NSString *path in files.list) {
            [self reindexPath:path];
        }
        [_fileSystem freeFileList:files];
    }
}

#pragma mark - Positions

/// The UTF-16 index of an LSP position in @a text, or NSNotFound.
static NSUInteger UDIndexOfPosition(NSString *text, NSDictionary *position) {
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

static BOOL UDIsNameCharacter(unichar c) {
    return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

/// The name at @a index (the cursor on or just after it), with the scopes
/// written before it: "lamp::flicker" on "flicker". Its start, through
/// @a start. Nil when there is none.
static NSString *UDNameAtIndex(NSString *text, NSUInteger index, NSUInteger *start) {
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
    if (start) *start = from;
    return [text substringWithRange:NSMakeRange(qualified, to - qualified)];
}

static NSDictionary *UDLocation(UDScriptDefinition *definition) {
    return @{
        @"uri": [UDScriptLanguageServer URIForPath:definition.path],
        @"range": @{
            @"start": @{ @"line": @(definition.line), @"character": @(definition.column) },
            @"end": @{ @"line": @(definition.line), @"character": @(definition.column + definition.length) },
        },
    };
}

#pragma mark - Requests

/// The document and position a textDocument/... request is about.
- (NSString *)textOfRequest:(NSDictionary *)params path:(NSString **)path index:(NSUInteger *)index {
    NSString *documentPath = [[self class] pathForURI:params[@"textDocument"][@"uri"] ?: @""];
    NSString *text = documentPath ? [self textOfPath:documentPath] : nil;
    if (text == nil) return nil;
    NSUInteger at = UDIndexOfPosition(text, params[@"position"]);
    if (at == NSNotFound) return nil;
    *path = documentPath;
    *index = at;
    return text;
}

/// What @a name names, as seen from @a path: its definitions in that
/// script, if it has any; otherwise everywhere.
- (NSArray<UDScriptDefinition *> *)definitionsOfName:(NSString *)name fromPath:(NSString *)path {
    NSArray<UDScriptDefinition *> *all = [_index definitionsOfName:name];
    NSArray *here = [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"path == %@", path]];
    return here.count > 0 ? here : all;
}

- (id)definition:(NSDictionary *)params {
    NSString *path = nil;
    NSUInteger index = 0;
    NSString *text = [self textOfRequest:params path:&path index:&index];
    NSString *name = text ? UDNameAtIndex(text, index, NULL) : nil;
    if (name == nil) return [NSNull null];
    NSMutableArray *locations = [NSMutableArray array];
    for (UDScriptDefinition *definition in [self definitionsOfName:name fromPath:path]) {
        [locations addObject:UDLocation(definition)];
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

- (id)completion:(NSDictionary *)params {
    NSString *path = nil;
    NSUInteger index = 0;
    NSString *text = [self textOfRequest:params path:&path index:&index];
    if (text == nil) return [NSNull null];
    NSUInteger start = index;
    while (start > 0 && UDIsNameCharacter([text characterAtIndex:start - 1])) start--;

    NSMutableArray *items = [NSMutableArray array];
    if (start > 0 && [text characterAtIndex:start - 1] == '.') {         // <object>.<event>
        for (NSString *name in [_events membersOfObject:@""]) {
            [items addObject:@{ @"label": name, @"kind": @(UDCompletionEvent),
                                @"detail": [_events functionParmsForName:name] ?: @"" }];
        }
    } else {
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (UDScriptDefinition *definition in _index.allDefinitions) {
            if ([seen containsObject:definition.name]) continue;
            [seen addObject:definition.name];
            [items addObject:@{ @"label": definition.name, @"kind": @(UDCompletionKind(definition.kind)) }];
        }
    }
    return @{ @"isIncomplete": @NO, @"items": items };
}

- (id)hover:(NSDictionary *)params {
    NSString *path = nil;
    NSUInteger index = 0;
    NSString *text = [self textOfRequest:params path:&path index:&index];
    NSString *name = text ? UDNameAtIndex(text, index, NULL) : nil;
    if (name == nil) return [NSNull null];

    NSString *value = [_events toolTipForName:name];
    if (value == nil) {
        UDScriptDefinition *definition = [self definitionsOfName:name fromPath:path].firstObject;
        NSArray<NSString *> *lines = [[self textOfPath:definition.path] componentsSeparatedByString:@"\n"];
        if (definition == nil || definition.line >= (NSInteger)lines.count) return [NSNull null];
        NSString *declaration = [lines[(NSUInteger)definition.line]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        value = [NSString stringWithFormat:@"%@\n\n%@:%ld", declaration, definition.path, (long)definition.line + 1];
    }
    return @{ @"contents": @{ @"kind": @"plaintext", @"value": value } };
}

- (NSDictionary *)capabilities {
    return @{
        @"capabilities": @{
            @"textDocumentSync": @1,                                // full text on each change
            @"definitionProvider": @YES,
            @"hoverProvider": @YES,
            @"completionProvider": @{ @"triggerCharacters": @[ @"." ] },
        },
        @"serverInfo": @{ @"name": @"udscript-lsp" },
    };
}

#pragma mark - Notifications

- (void)didOpen:(NSDictionary *)params {
    NSString *path = [[self class] pathForURI:params[@"textDocument"][@"uri"] ?: @""];
    NSString *text = params[@"textDocument"][@"text"];
    if (path == nil || ![text isKindOfClass:[NSString class]]) return;
    _openTexts[path] = text;
    [self reindexPath:path];
}

- (void)didChange:(NSDictionary *)params {
    NSString *path = [[self class] pathForURI:params[@"textDocument"][@"uri"] ?: @""];
    NSString *text = [params[@"contentChanges"] lastObject][@"text"];
    if (path == nil || ![text isKindOfClass:[NSString class]]) return;
    _openTexts[path] = text;
    [self reindexPath:path];
}

- (void)didClose:(NSDictionary *)params {
    NSString *path = [[self class] pathForURI:params[@"textDocument"][@"uri"] ?: @""];
    if (path == nil) return;
    [_openTexts removeObjectForKey:path];
    [self reindexPath:path];
}

- (void)didChangeWatchedFiles:(NSDictionary *)params {
    for (NSDictionary *change in params[@"changes"]) {
        NSString *path = [[self class] pathForURI:change[@"uri"] ?: @""];
        if (path != nil && [path.pathExtension caseInsensitiveCompare:@"script"] == NSOrderedSame) {
            [self reindexPath:path];
        }
    }
}

#pragma mark - Messages

- (NSDictionary *)replyToMessage:(NSDictionary *)message {
    NSString *method = message[@"method"];
    id identifier = message[@"id"];
    NSDictionary *params = [message[@"params"] isKindOfClass:[NSDictionary class]] ? message[@"params"] : @{};

    if (identifier == nil) {                                          // a notification
        if ([method isEqualToString:@"textDocument/didOpen"]) [self didOpen:params];
        else if ([method isEqualToString:@"textDocument/didChange"]) [self didChange:params];
        else if ([method isEqualToString:@"textDocument/didClose"]) [self didClose:params];
        else if ([method isEqualToString:@"workspace/didChangeWatchedFiles"]) [self didChangeWatchedFiles:params];
        else if ([method isEqualToString:@"exit"]) _exited = YES;
        return nil;
    }

    id result = nil;
    if ([method isEqualToString:@"initialize"]) {
        [self indexFileSystem];
        result = [self capabilities];
    } else if ([method isEqualToString:@"shutdown"]) {
        _shutDown = YES;
        result = [NSNull null];
    } else if ([method isEqualToString:@"textDocument/definition"]) {
        result = [self definition:params];
    } else if ([method isEqualToString:@"textDocument/completion"]) {
        result = [self completion:params];
    } else if ([method isEqualToString:@"textDocument/hover"]) {
        result = [self hover:params];
    }
    if (result == nil) {
        return @{ @"jsonrpc": @"2.0", @"id": identifier,
                  @"error": @{ @"code": @(-32601), @"message": [NSString stringWithFormat:@"%@: no such method", method] } };
    }
    return @{ @"jsonrpc": @"2.0", @"id": identifier, @"result": result };
}

@end
