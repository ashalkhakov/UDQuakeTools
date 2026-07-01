/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEditorService.m — GUI editing operations with undo/redo support.
 */

#import "UDGuiEditorService.h"

#import "UDDeclParser.h"

static NSString *const UDGuiDocumentCodecErrorDomain = @"com.udquake.error.guidocumentcodec";

typedef NS_ENUM(NSInteger, UDGuiDocumentCodecErrorCode) {
    UDGuiDocumentCodecErrorCodeUnexpectedEOF = 1,
    UDGuiDocumentCodecErrorCodeUnexpectedToken = 2,
};

@interface UDGuiDeclCursor : NSObject

- (instancetype)initWithText:(NSString *)text;
- (UDIdToken *)peekToken;
- (UDIdToken *)readToken;
- (void)unreadToken:(UDIdToken *)token;
- (BOOL)containsNewlineBetweenToken:(UDIdToken *)leftToken andToken:(UDIdToken *)rightToken;
- (NSString *)sourceSliceFromToken:(UDIdToken *)startToken toToken:(UDIdToken *)endToken;

@end

@interface UDGuiDeclCursor ()
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UDIdLexer *lexer;
@property (nullable, nonatomic, strong) UDIdToken *lookahead;
@end

@implementation UDGuiDeclCursor

- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (!self) {
        return nil;
    }

    _text = [text copy];
    _lexer = [[UDIdLexer alloc] initWithText:_text];
    return self;
}

- (UDIdToken *)peekToken {
    if (!self.lookahead) {
        self.lookahead = [self.lexer nextToken];
    }
    return self.lookahead;
}

- (UDIdToken *)readToken {
    if (self.lookahead) {
        UDIdToken *token = self.lookahead;
        self.lookahead = nil;
        return token;
    }
    return [self.lexer nextToken];
}

- (void)unreadToken:(UDIdToken *)token {
    self.lookahead = token;
}

- (BOOL)containsNewlineBetweenToken:(UDIdToken *)leftToken andToken:(UDIdToken *)rightToken {
    if (!leftToken || !rightToken) {
        return NO;
    }
    if (rightToken.start < leftToken.end || leftToken.end > self.text.length || rightToken.start > self.text.length) {
        return NO;
    }

    NSRange gapRange = NSMakeRange(leftToken.end, rightToken.start - leftToken.end);
    if (gapRange.length == 0) {
        return NO;
    }

    NSString *gapText = [self.text substringWithRange:gapRange];
    return [gapText rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound;
}

- (NSString *)sourceSliceFromToken:(UDIdToken *)startToken toToken:(UDIdToken *)endToken {
    if (!startToken || !endToken) {
        return @"";
    }
    if (endToken.end < startToken.start || startToken.start > self.text.length || endToken.end > self.text.length) {
        return @"";
    }

    return [self.text substringWithRange:NSMakeRange(startToken.start, endToken.end - startToken.start)];
}

@end

@interface UDGuiDocumentCodec ()
- (nullable UDGuiWindowNode *)parseWindowDefinition:(UDDeclDefinition *)definition
                                              error:(NSError **)error;
- (nullable UDGuiWindowNode *)parseWindowBodyWithClassName:(NSString *)className
                                                       name:(NSString *)name
                                                     cursor:(UDGuiDeclCursor *)cursor
                                                      error:(NSError **)error;
- (nullable NSString *)parseBlockValueStartingWithToken:(UDIdToken *)startToken
                                                 cursor:(UDGuiDeclCursor *)cursor
                                                  error:(NSError **)error;
- (BOOL)isWindowClassIdentifier:(NSString *)identifier;
- (BOOL)isIdentifierLikeLiteral:(NSString *)value;
- (BOOL)shouldQuoteSerializedPropertyValue:(NSString *)value;
- (NSString *)serializePropertyValue:(NSString *)value;
@end

@implementation UDGuiDocumentCodec

- (nullable UDGuiDocument *)parseDocumentFromText:(NSString *)text
                                sourceVirtualPath:(NSString *)sourceVirtualPath
                                            error:(NSError **)error {
    NSParameterAssert(text != nil);
    NSParameterAssert(sourceVirtualPath.length > 0);

    UDGuiDocument *document = [[UDGuiDocument alloc] initWithSourceVirtualPath:sourceVirtualPath];
    UDDeclParser *declParser = [[UDDeclParser alloc] init];
    NSArray<UDDeclDefinition *> *definitions = [declParser parseDefinitionsFromText:text
                                                                   sourceVirtualPath:sourceVirtualPath
                                                                               error:error];
    if (!definitions) {
        return nil;
    }

    for (UDDeclDefinition *definition in definitions) {
        UDGuiWindowNode *window = [self parseWindowDefinition:definition error:error];
        if (!window) {
            return nil;
        }
        [document addRootWindow:window];
    }

    if (error) {
        *error = nil;
    }
    return document;
}

- (nullable UDGuiWindowNode *)parseWindowDefinition:(UDDeclDefinition *)definition
                                              error:(NSError **)error {
    UDGuiDeclCursor *cursor = [[UDGuiDeclCursor alloc] initWithText:definition.body ?: @""];

    UDIdToken *classToken = [cursor readToken];
    UDIdToken *nameToken = [cursor readToken];
    UDIdToken *openBrace = [cursor readToken];

    if (classToken.kind == UDIdTokenKindEOF || nameToken.kind == UDIdTokenKindEOF || openBrace.kind == UDIdTokenKindEOF) {
        if (error) {
            *error = [NSError errorWithDomain:UDGuiDocumentCodecErrorDomain
                                         code:UDGuiDocumentCodecErrorCodeUnexpectedEOF
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unexpected EOF while reading window header."}];
        }
        return nil;
    }

    if (![openBrace.text isEqualToString:@"{"]) {
        if (error) {
            *error = [NSError errorWithDomain:UDGuiDocumentCodecErrorDomain
                                         code:UDGuiDocumentCodecErrorCodeUnexpectedToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Expected '{' after window header."}];
        }
        return nil;
    }

    return [self parseWindowBodyWithClassName:classToken.text name:nameToken.text cursor:cursor error:error];
}

- (nullable UDGuiWindowNode *)parseWindowBodyWithClassName:(NSString *)className
                                                       name:(NSString *)name
                                                     cursor:(UDGuiDeclCursor *)cursor
                                                      error:(NSError **)error {
    UDGuiWindowNode *node = [UDGuiWindowNode windowNodeWithClassName:className name:name];

    while (YES) {
        UDIdToken *keyOrClassToken = [cursor readToken];
        if (keyOrClassToken.kind == UDIdTokenKindEOF) {
            if (error) {
                *error = [NSError errorWithDomain:UDGuiDocumentCodecErrorDomain
                                             code:UDGuiDocumentCodecErrorCodeUnexpectedEOF
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unexpected EOF while reading window body."}];
            }
            return nil;
        }

        if (keyOrClassToken.text.length == 0) {
            continue;
        }

        if (keyOrClassToken.kind == UDIdTokenKindPunctuation && [keyOrClassToken.text isEqualToString:@"}"]) {
            break;
        }

        if (keyOrClassToken.kind != UDIdTokenKindIdentifier && keyOrClassToken.kind != UDIdTokenKindString) {
            continue;
        }

        UDIdToken *secondToken = [cursor readToken];
        if (secondToken.kind == UDIdTokenKindEOF) {
            if (error) {
                *error = [NSError errorWithDomain:UDGuiDocumentCodecErrorDomain
                                             code:UDGuiDocumentCodecErrorCodeUnexpectedEOF
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unexpected EOF while reading token."}];
            }
            return nil;
        }

        if (secondToken.text.length == 0) {
            [node setPropertyValue:@"" forKey:keyOrClassToken.text ?: @""];
            continue;
        }

        if (secondToken.kind == UDIdTokenKindPunctuation && [secondToken.text isEqualToString:@"{"]) {
            NSString *blockValue = [self parseBlockValueStartingWithToken:secondToken cursor:cursor error:error];
            if (!blockValue) {
                return nil;
            }
            [node setPropertyValue:blockValue forKey:keyOrClassToken.text ?: @""];
            continue;
        }

        if ([keyOrClassToken.text caseInsensitiveCompare:@"definefloat"] == NSOrderedSame ||
            [keyOrClassToken.text caseInsensitiveCompare:@"definevec4"] == NSOrderedSame) {
            // TODO: Revisit Doom 3 GUI variable definitions that use "$"-prefixed names
            // and expression values such as pdhalffade[time*0.001]/1.5. They appear in
            // shipped assets like guis/admin/office.gui and likely need richer token
            // handling and/or explicit expression modeling beyond the current name/value split.
            UDIdToken *lastValueToken = secondToken;
            while (YES) {
                UDIdToken *valueToken = [cursor peekToken];
                if (valueToken.kind == UDIdTokenKindEOF) {
                    break;
                }
                if (valueToken.kind == UDIdTokenKindPunctuation && [valueToken.text isEqualToString:@"}"]) {
                    break;
                }
                if ([cursor containsNewlineBetweenToken:lastValueToken andToken:valueToken]) {
                    break;
                }
                lastValueToken = [cursor readToken];
            }

            NSString *fullValue = @"";
            if (lastValueToken != secondToken) {
                fullValue = [[cursor sourceSliceFromToken:lastValueToken == secondToken ? secondToken : [cursor peekToken] toToken:lastValueToken]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }

            NSString *namePart = [cursor sourceSliceFromToken:secondToken toToken:secondToken] ?: @"";
            NSString *valuePart = @"";
            if (lastValueToken != secondToken) {
                UDIdToken *firstValueToken = nil;
                UDGuiDeclCursor *dummyCursor = cursor;
                (void)dummyCursor;
            }

            NSString *lineText = [[cursor sourceSliceFromToken:secondToken toToken:lastValueToken]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *variableName = secondToken.text ?: @"";
            NSString *variableValue = @"";
            if (lineText.length > variableName.length) {
                variableValue = [[lineText substringFromIndex:variableName.length]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }

            UDGuiVariableDefinitionType type = [keyOrClassToken.text caseInsensitiveCompare:@"definevec4"] == NSOrderedSame
                ? UDGuiVariableDefinitionTypeVec4
                : UDGuiVariableDefinitionTypeFloat;
            [node addVariableDefinition:[[UDGuiVariableDefinition alloc] initWithType:type
                                                                           name:variableName
                                                                          value:variableValue]];
            continue;
        }

        UDIdToken *thirdToken = [cursor peekToken];
        if (thirdToken.kind == UDIdTokenKindPunctuation && [thirdToken.text isEqualToString:@"{"] && [self isWindowClassIdentifier:keyOrClassToken.text]) {
            (void)[cursor readToken];
            UDGuiWindowNode *child = [self parseWindowBodyWithClassName:keyOrClassToken.text
                                                                    name:secondToken.text
                                                                  cursor:cursor
                                                                   error:error];
            if (!child) {
                return nil;
            }
            [node addChild:child];
            continue;
        }

        if (thirdToken.kind == UDIdTokenKindPunctuation && [thirdToken.text isEqualToString:@"{"]) {
            (void)[cursor readToken];
            NSString *blockValue = [self parseBlockValueStartingWithToken:thirdToken cursor:cursor error:error];
            if (!blockValue) {
                return nil;
            }
            NSString *fullValue = [NSString stringWithFormat:@"%@ %@", [cursor sourceSliceFromToken:secondToken toToken:secondToken], blockValue];
            [node setPropertyValue:[fullValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                           forKey:keyOrClassToken.text ?: @""];
            continue;
        }

        UDIdToken *lastValueToken = secondToken;
        while (YES) {
            UDIdToken *valueToken = [cursor peekToken];
            if (valueToken.kind == UDIdTokenKindEOF) {
                break;
            }
            if (valueToken.kind == UDIdTokenKindPunctuation && [valueToken.text isEqualToString:@"}"]) {
                break;
            }
            if ([cursor containsNewlineBetweenToken:lastValueToken andToken:valueToken]) {
                break;
            }
            lastValueToken = [cursor readToken];
        }

        NSString *value = nil;
        if (secondToken == lastValueToken && secondToken.kind == UDIdTokenKindString) {
            // Store quoted literals without syntax quotes so the editor shows plain values.
            value = secondToken.text ?: @"";
        } else {
            value = [[cursor sourceSliceFromToken:secondToken toToken:lastValueToken]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        [node setPropertyValue:value forKey:keyOrClassToken.text ?: @""];
    }

    return node;
}

- (nullable NSString *)parseBlockValueStartingWithToken:(UDIdToken *)startToken
                                                 cursor:(UDGuiDeclCursor *)cursor
                                                  error:(NSError **)error {
    NSInteger blockDepth = 1;
    UDIdToken *endToken = startToken;

    while (blockDepth > 0) {
        UDIdToken *token = [cursor readToken];
        if (token.kind == UDIdTokenKindEOF) {
            if (error) {
                *error = [NSError errorWithDomain:UDGuiDocumentCodecErrorDomain
                                             code:UDGuiDocumentCodecErrorCodeUnexpectedEOF
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unexpected EOF while reading script block."}];
            }
            return nil;
        }

        if (token.kind == UDIdTokenKindPunctuation) {
            if ([token.text isEqualToString:@"{"]) {
                blockDepth++;
            } else if ([token.text isEqualToString:@"}"]) {
                blockDepth--;
            }
        }

        endToken = token;
    }

    return [[cursor sourceSliceFromToken:startToken toToken:endToken]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (BOOL)isWindowClassIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return NO;
    }

    return [identifier.lowercaseString hasSuffix:@"def"];
}

- (nullable NSString *)serializeDocument:(UDGuiDocument *)document error:(NSError **)error {
    NSParameterAssert(document != nil);

    NSMutableString *text = [NSMutableString string];
    for (NSUInteger idx = 0; idx < document.rootWindows.count; idx++) {
        UDGuiWindowNode *window = [document.rootWindows objectAtIndex:idx];
        [self appendWindow:window toText:text indentLevel:0];
        if (idx + 1 < document.rootWindows.count) {
            [text appendString:@"\n\n"];
        }
    }

    if (error) {
        *error = nil;
    }
    return [text copy];
}

- (void)appendWindow:(UDGuiWindowNode *)window
              toText:(NSMutableString *)text
         indentLevel:(NSUInteger)indentLevel {
    NSString *indent = [@"" stringByPaddingToLength:(indentLevel * 4) withString:@" " startingAtIndex:0];
    [text appendFormat:@"%@%@ %@ {\n", indent, window.className, window.name];

    for (UDGuiVariableDefinition *definition in window.variableDefinitions) {
        if (definition.value.length > 0) {
            [text appendFormat:@"%@    %@ %@ %@\n", indent, definition.keyword, definition.name, definition.value];
        } else {
            [text appendFormat:@"%@    %@ %@\n", indent, definition.keyword, definition.name];
        }
    }

    for (UDGuiProperty *property in window.properties) {
        [text appendFormat:@"%@    %@ %@\n", indent, property.key, [self serializePropertyValue:property.value ?: @""]];
    }

    for (UDGuiWindowNode *child in window.children) {
        [self appendWindow:child toText:text indentLevel:indentLevel + 1];
    }

    [text appendFormat:@"%@}", indent];
    if (indentLevel > 0) {
        [text appendString:@"\n"];
    }
}

- (BOOL)isIdentifierLikeLiteral:(NSString *)value {
    if (value.length == 0) {
        return NO;
    }

    NSCharacterSet *alnum = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger idx = 0; idx < value.length; idx++) {
        unichar ch = [value characterAtIndex:idx];
        if ([alnum characterIsMember:ch]) {
            continue;
        }

        switch (ch) {
            case '_':
            case '/':
            case '.':
            case ':':
            case '-':
            case '*':
            case '$':
            case '@':
                continue;
            default:
                return NO;
        }
    }

    return YES;
}

- (BOOL)shouldQuoteSerializedPropertyValue:(NSString *)value {
    if (value.length == 0) {
        return YES;
    }

    if ([value hasPrefix:@"{"] || [value hasPrefix:@"("] || [value hasPrefix:@"["]) {
        return NO;
    }

    if ([value rangeOfString:@"{"].location != NSNotFound ||
        [value rangeOfString:@"}"].location != NSNotFound ||
        [value rangeOfString:@";"].location != NSNotFound ||
        [value rangeOfString:@","].location != NSNotFound) {
        return NO;
    }

    if ([value hasPrefix:@"#"]) {
        return YES;
    }

    if ([value rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
        return YES;
    }

    return ![self isIdentifierLikeLiteral:value];
}

- (NSString *)serializePropertyValue:(NSString *)value {
    if (![self shouldQuoteSerializedPropertyValue:value]) {
        return value;
    }

    NSString *escaped = [[value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
        stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

@end

@interface UDGuiEditorService ()
@property (nonatomic, readwrite, strong) UDGuiDocument *document;
@property (nonatomic, readwrite, strong) NSUndoManager *undoManager;
@end

@implementation UDGuiEditorService

- (instancetype)initWithDocument:(UDGuiDocument *)document undoManager:(NSUndoManager *)undoManager {
    NSParameterAssert(document != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _document = document;
    _undoManager = undoManager ?: [[NSUndoManager alloc] init];
    return self;
}

- (void)replaceDocument:(UDGuiDocument *)document {
    NSParameterAssert(document != nil);

    UDGuiDocument *oldDocument = self.document;
    self.document = document;

    [[self.undoManager prepareWithInvocationTarget:self] replaceDocument:oldDocument];
}

- (void)updatePropertyForWindow:(UDGuiWindowNode *)window
                            key:(NSString *)key
                          value:(NSString *)value {
    NSParameterAssert(window != nil);
    NSParameterAssert(key.length > 0);
    NSParameterAssert(value != nil);

    UDGuiProperty *existing = [window propertyForKey:key];
    NSString *oldValue = existing ? existing.value : nil;

    [window setPropertyValue:value forKey:key];

    if (oldValue) {
        [[self.undoManager prepareWithInvocationTarget:self] updatePropertyForWindow:window key:key value:oldValue];
    } else {
        [[self.undoManager prepareWithInvocationTarget:self] removePropertyForWindow:window key:key];
    }
}

- (void)updateWindow:(UDGuiWindowNode *)window className:(NSString *)className {
    NSParameterAssert(window != nil);
    NSParameterAssert(className.length > 0);

    NSString *oldClassName = window.className;
    if ([oldClassName isEqualToString:className]) {
        return;
    }

    window.className = className;
    [[self.undoManager prepareWithInvocationTarget:self] updateWindow:window className:oldClassName];
}

- (void)updateWindow:(UDGuiWindowNode *)window name:(NSString *)name {
    NSParameterAssert(window != nil);
    NSParameterAssert(name.length > 0);

    NSString *oldName = window.name;
    if ([oldName isEqualToString:name]) {
        return;
    }

    window.name = name;
    [[self.undoManager prepareWithInvocationTarget:self] updateWindow:window name:oldName];
}

- (void)renamePropertyForWindow:(UDGuiWindowNode *)window
                         fromKey:(NSString *)oldKey
                           toKey:(NSString *)newKey
                           value:(NSString *)value {
    NSParameterAssert(window != nil);
    NSParameterAssert(oldKey.length > 0);
    NSParameterAssert(newKey.length > 0);
    NSParameterAssert(value != nil);

    if ([oldKey isEqualToString:newKey]) {
        [self updatePropertyForWindow:window key:newKey value:value];
        return;
    }

    UDGuiProperty *existing = [window propertyForKey:oldKey];
    if (!existing) {
        [self updatePropertyForWindow:window key:newKey value:value];
        return;
    }

    NSString *oldValue = existing.value;
    [window removePropertyForKey:oldKey];
    [window setPropertyValue:value forKey:newKey];
    [[self.undoManager prepareWithInvocationTarget:self] renamePropertyForWindow:window fromKey:newKey toKey:oldKey value:oldValue];
}

- (void)removePropertyForWindow:(UDGuiWindowNode *)window key:(NSString *)key {
    NSParameterAssert(window != nil);
    NSParameterAssert(key.length > 0);

    UDGuiProperty *existing = [window propertyForKey:key];
    if (!existing) {
        return;
    }

    [window removePropertyForKey:key];
    [[self.undoManager prepareWithInvocationTarget:self] updatePropertyForWindow:window key:key value:existing.value];
}

- (void)addWindow:(UDGuiWindowNode *)window toParent:(UDGuiWindowNode *)parent atIndex:(NSUInteger)index {
    NSParameterAssert(window != nil);

    if (parent) {
        [parent insertChild:window atIndex:index];
    } else {
        [self.document insertRootWindow:window atIndex:index];
    }

    [[self.undoManager prepareWithInvocationTarget:self] removeWindow:window];
}

- (void)removeWindow:(UDGuiWindowNode *)window {
    NSParameterAssert(window != nil);

    UDGuiWindowNode *parent = window.parent;
    NSUInteger index = NSNotFound;

    if (parent) {
        index = [parent indexOfChild:window];
        [parent removeChild:window];
    } else {
        index = [self.document indexOfRootWindow:window];
        [self.document removeRootWindow:window];
    }

    if (index == NSNotFound) {
        return;
    }

    [[self.undoManager prepareWithInvocationTarget:self] addWindow:window toParent:parent atIndex:index];
}

- (void)moveWindow:(UDGuiWindowNode *)window toNewParent:(UDGuiWindowNode *)newParent atIndex:(NSUInteger)index {
    NSParameterAssert(window != nil);

    UDGuiWindowNode *oldParent = window.parent;
    NSUInteger oldIndex = oldParent ? [oldParent indexOfChild:window] : [self.document indexOfRootWindow:window];

    if (oldParent) {
        [oldParent removeChild:window];
    } else {
        [self.document removeRootWindow:window];
    }

    if (newParent) {
        [newParent insertChild:window atIndex:index];
    } else {
        [self.document insertRootWindow:window atIndex:index];
    }

    [[self.undoManager prepareWithInvocationTarget:self] moveWindow:window toNewParent:oldParent atIndex:oldIndex];
}

@end
