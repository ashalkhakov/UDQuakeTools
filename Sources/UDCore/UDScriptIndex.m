//
//  UDScriptIndex.m
//  UDCore
//

#import "UDScriptIndex.h"
#import "idLexer.h"

@implementation UDScriptDefinition

- (instancetype)initWithKind:(UDScriptDefinitionKind)kind name:(NSString *)name qualifiedName:(NSString *)qualifiedName
                        path:(NSString *)path line:(NSInteger)line column:(NSInteger)column {
    if (!(self = [super init])) return nil;
    _kind = kind;
    _name = [name copy];
    _qualifiedName = [qualifiedName copy];
    _path = [path copy];
    _line = line;
    _column = column;
    _length = (NSInteger)name.length;
    return self;
}

- (BOOL)isPrototype {
    return _kind == UDScriptDefinitionFunctionPrototype || _kind == UDScriptDefinitionMethodPrototype;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %@:%ld:%ld (%ld)", _qualifiedName, _path, (long)_line, (long)_column, (long)_kind];
}

@end

// One script's walk: the lexer over its bytes, and where its definitions go.
@interface UDScriptWalk : NSObject {
@public
    idLexer *lexer;
    NSData *bytes;               // the text, UTF-8, NUL-terminated
    NSString *path;
    NSMutableArray<UDScriptDefinition *> *definitions;
}
@end

@implementation UDScriptWalk

static BOOL UDIs(const idToken *token, const char *text) {
    return strcmp(token->text, text) == 0;
}

/// The next token, past the preprocessor's lines (#include, #define, ...).
- (BOOL)next:(idToken *)token {
    while ([lexer readToken:token error:NULL]) {
        if (token->type == TT_PUNCTUATION && UDIs(token, "#")) {
            [lexer skipRestOfLine:NULL];
            continue;
        }
        return YES;
    }
    return NO;
}

/// Where the name starts, from its token (which may have been read a while
/// ago): 0-based line, UTF-16 column.
- (void)add:(UDScriptDefinitionKind)kind name:(const idToken *)token scope:(NSString *)scope {
    const char *start = (const char *)bytes.bytes;
    NSInteger offset = token->whiteSpaceEnd_p - start;
    NSInteger line = 0, lineStart = 0;
    for (NSInteger i = 0; i < offset; i++) {
        if (start[i] == '\n') { line++; lineStart = i + 1; }
    }
    NSString *before = [[NSString alloc] initWithBytes:start + lineStart length:(NSUInteger)(offset - lineStart)
                                              encoding:NSUTF8StringEncoding];
    NSString *name = [NSString stringWithUTF8String:token->text];
    [definitions addObject:[[UDScriptDefinition alloc] initWithKind:kind name:name
                                                      qualifiedName:[scope stringByAppendingString:name]
                                                               path:path line:line column:(NSInteger)before.length]];
}

/// Past a parenthesized list, its '(' already read.
- (void)skipParentheses {
    idToken token;
    idToken_Init(&token);
    int depth = 1;
    while (depth > 0 && [self next:&token]) {
        if (UDIs(&token, "(")) depth++;
        else if (UDIs(&token, ")")) depth--;
    }
}

/// Past a braced body, its '{' already read.
- (void)skipBody {
    idToken token;
    idToken_Init(&token);
    int depth = 1;
    while (depth > 0 && [self next:&token]) {
        if (UDIs(&token, "{")) depth++;
        else if (UDIs(&token, "}")) depth--;
    }
}

/// ParseFunctionDef after the parameters: a body (a definition) or ';'.
- (BOOL)functionBody {
    idToken token;
    idToken_Init(&token);
    if (![self next:&token]) return NO;
    if (UDIs(&token, "{")) {
        [self skipBody];
        return YES;
    }
    return NO;                  // ';': a prototype
}

/// ParseObjectDef, after "object <name>".
- (void)objectNamed:(NSString *)objectName {
    idToken token, name;
    idToken_Init(&token);
    idToken_Init(&name);
    NSString *scope = [objectName stringByAppendingString:@"::"];
    while ([self next:&token] && !UDIs(&token, "{")) {}       // ": <parent>"
    while ([self next:&token]) {
        if (UDIs(&token, "}")) break;
        if (UDIs(&token, ";")) continue;
        if (![self next:&name]) return;                         // <type> <name>
        if (![self next:&token]) return;
        if (UDIs(&token, "(")) {
            [self skipParentheses];
            NSInteger before = (NSInteger)definitions.count;
            [self add:UDScriptDefinitionMethodPrototype name:&name scope:scope];
            if ([self functionBody]) {
                UDScriptDefinition *method = definitions[(NSUInteger)before];
                [definitions replaceObjectAtIndex:(NSUInteger)before withObject:
                    [[UDScriptDefinition alloc] initWithKind:UDScriptDefinitionMethod name:method.name
                                               qualifiedName:method.qualifiedName path:method.path
                                                        line:method.line column:method.column]];
            }
        } else {
            [self add:UDScriptDefinitionField name:&name scope:scope];
            while (!UDIs(&token, ";") && [self next:&token]) {}
        }
    }
    [self next:&token];                                          // ';'
}

/// ParseDefs, until the '}' that closes the namespace (or the end).
- (void)definitionsInScope:(NSString *)scope {
    idToken token, name, member;
    idToken_Init(&token);
    idToken_Init(&name);
    idToken_Init(&member);
    while ([self next:&token]) {
        if (UDIs(&token, ";")) continue;
        if (UDIs(&token, "}")) return;

        if (UDIs(&token, "scriptEvent")) {                       // ParseEventDef
            if (![self next:&token] || ![self next:&name]) return;
            [self add:UDScriptDefinitionEvent name:&name scope:scope];
            while ([self next:&token] && !UDIs(&token, ";")) {}
            continue;
        }
        if (UDIs(&token, "namespace")) {                         // ParseNamespace
            if (![self next:&name]) return;
            [self add:UDScriptDefinitionNamespace name:&name scope:scope];
            NSString *inner = [NSString stringWithFormat:@"%@%s::", scope, name.text];
            if (![self next:&token]) return;                    // '{'
            [self definitionsInScope:inner];
            continue;
        }
        if (UDIs(&token, "object")) {                            // ParseObjectDef
            if (![self next:&name]) return;
            [self add:UDScriptDefinitionObject name:&name scope:scope];
            [self objectNamed:[NSString stringWithFormat:@"%@%s", scope, name.text]];
            continue;
        }

        // <type> <name> ...
        if (![self next:&name]) return;
        if (![self next:&token]) return;
        if (UDIs(&token, "::")) {                                // <type> <object>::<method>( ... )
            if (![self next:&member]) return;
            NSString *objectScope = [NSString stringWithFormat:@"%@%s::", scope, name.text];
            if (![self next:&token]) return;                    // '('
            [self skipParentheses];
            NSInteger at = (NSInteger)definitions.count;
            [self add:UDScriptDefinitionMethod name:&member scope:objectScope];
            if (![self functionBody]) {
                UDScriptDefinition *prototype = definitions[(NSUInteger)at];
                [definitions replaceObjectAtIndex:(NSUInteger)at withObject:
                    [[UDScriptDefinition alloc] initWithKind:UDScriptDefinitionMethodPrototype name:prototype.name
                                               qualifiedName:prototype.qualifiedName path:prototype.path
                                                        line:prototype.line column:prototype.column]];
            }
            continue;
        }
        if (UDIs(&token, "(")) {                                 // a function, or its prototype
            [self skipParentheses];
            NSInteger at = (NSInteger)definitions.count;
            [self add:UDScriptDefinitionFunction name:&name scope:scope];
            if (![self functionBody]) {
                UDScriptDefinition *prototype = definitions[(NSUInteger)at];
                [definitions replaceObjectAtIndex:(NSUInteger)at withObject:
                    [[UDScriptDefinition alloc] initWithKind:UDScriptDefinitionFunctionPrototype name:prototype.name
                                               qualifiedName:prototype.qualifiedName path:prototype.path
                                                        line:prototype.line column:prototype.column]];
            }
            continue;
        }
        // ParseVariableDef: <name> [= <value>] [, <name> [= <value>]] ;
        [self add:UDScriptDefinitionVariable name:&name scope:scope];
        int depth = 0;
        BOOL nameNext = NO;
        do {
            if (nameNext && depth == 0) {
                [self add:UDScriptDefinitionVariable name:&token scope:scope];
                nameNext = NO;
                continue;
            }
            if (UDIs(&token, "(")) depth++;
            else if (UDIs(&token, ")")) depth--;
            else if (depth == 0 && UDIs(&token, ",")) nameNext = YES;
            else if (depth == 0 && UDIs(&token, ";")) break;
        } while ([self next:&token]);
    }
}

@end

@implementation UDScriptIndex {
    NSMutableDictionary<NSString *, NSArray<UDScriptDefinition *> *> *_byPath;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _byPath = [NSMutableDictionary dictionary];
    return self;
}

+ (NSArray<UDScriptDefinition *> *)definitionsInText:(NSString *)text path:(NSString *)path {
    NSMutableData *bytes = [[text dataUsingEncoding:NSUTF8StringEncoding] mutableCopy] ?: [NSMutableData data];
    int length = (int)bytes.length;
    [bytes appendBytes:"" length:1];        // NUL-terminated, as idLexer expects

    UDScriptWalk *walk = [[UDScriptWalk alloc] init];
    walk->lexer = [[idLexer alloc] initWithFlags:LEXFL_NOERRORS | LEXFL_NOWARNINGS | LEXFL_NOFATALERRORS
                                      fileSystem:nil];
    walk->bytes = bytes;
    walk->path = [path copy];
    walk->definitions = [NSMutableArray array];
    if ([walk->lexer loadMemory:bytes.bytes length:length name:path startLine:1 error:NULL]) {
        [walk definitionsInScope:@""];
    }
    return walk->definitions;
}

- (void)setText:(NSString *)text forPath:(NSString *)path {
    _byPath[path] = [[self class] definitionsInText:text path:path];
}

- (void)removePath:(NSString *)path {
    [_byPath removeObjectForKey:path];
}

- (BOOL)hasPath:(NSString *)path {
    return _byPath[path] != nil;
}

- (NSArray<UDScriptDefinition *> *)allDefinitions {
    NSMutableArray *all = [NSMutableArray array];
    for (NSString *path in [_byPath.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [all addObjectsFromArray:_byPath[path]];
    }
    return all;
}

- (NSArray<UDScriptDefinition *> *)definitionsOfName:(NSString *)name {
    BOOL qualified = [name rangeOfString:@"::"].location != NSNotFound;
    NSMutableArray<UDScriptDefinition *> *found = [NSMutableArray array];
    for (UDScriptDefinition *definition in self.allDefinitions) {
        if (qualified ? [definition.qualifiedName isEqualToString:name] : [definition.name isEqualToString:name]) {
            [found addObject:definition];
        }
    }
    // Definitions first, then prototypes and declarations; stable otherwise.
    return [found sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(UDScriptDefinition *a, UDScriptDefinition *b) {
        BOOL pa = [a isPrototype], pb = [b isPrototype];
        return pa == pb ? NSOrderedSame : (pa ? NSOrderedDescending : NSOrderedAscending);
    }];
}

@end
