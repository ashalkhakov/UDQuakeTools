/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiDocumentCodec.m — parse/serialize GUI documents.
 */

#import "UDGuiDocumentCodec.h"

#import "UDDeclParser.h"

@interface UDGuiExpressionSerializer : NSObject <UDGuiExpressionVisitor>
@end

@implementation UDGuiExpressionSerializer

- (id)visitNumberLiteralExpression:(UDGuiNumberLiteralExpression *)expression {
    return expression.value;
}

- (id)visitStringLiteralExpression:(UDGuiStringLiteralExpression *)expression {
    return [NSString stringWithFormat:@"\"%@\"", expression.value];
}

- (id)visitVariableExpression:(UDGuiVariableExpression *)expression {
    return expression.name;
}

- (id)visitParenthesizedExpression:(UDGuiParenthesizedExpression *)expression {
    return [NSString stringWithFormat:@"( %@ )", [expression.expression acceptVisitor:self]];
}

- (id)visitUnaryExpression:(UDGuiUnaryExpression *)expression {
    return [NSString stringWithFormat:@"%@%@", expression.operatorString, [expression.operand acceptVisitor:self]];
}

- (id)visitBinaryExpression:(UDGuiBinaryExpression *)expression {
    return [NSString stringWithFormat:@"%@ %@ %@", [expression.left acceptVisitor:self], expression.operatorString, [expression.right acceptVisitor:self]];
}

@end

static NSString *const UDGuiDocumentCodecErrorDomain = @"com.udquake.error.guidocumentcodec";
static NSString *const UDGuiRawScriptBodyCommandKeyword = @"__ud_raw_script_body__";

typedef NS_ENUM(NSInteger, UDGuiDocumentCodecErrorCode) {
    UDGuiDocumentCodecErrorCodeUnexpectedEOF = 1,
    UDGuiDocumentCodecErrorCodeUnexpectedToken = 2,
};

static UDGuiEventHandlerType UDGuiEventHandlerTypeForIdentifier(NSString *identifier) {
    NSString *lower = identifier.lowercaseString;
    if ([lower isEqualToString:@"ontime"]) {
        return UDGuiEventHandlerTypeOnTime;
    }
    if ([lower isEqualToString:@"onnamedevent"]) {
        return UDGuiEventHandlerTypeOnNamedEvent;
    }
    if ([lower isEqualToString:@"onaction"]) {
        return UDGuiEventHandlerTypeOnAction;
    }
    if ([lower isEqualToString:@"onactionrelease"]) {
        return UDGuiEventHandlerTypeOnActionRelease;
    }
    if ([lower isEqualToString:@"onmouseenter"]) {
        return UDGuiEventHandlerTypeOnMouseEnter;
    }
    if ([lower isEqualToString:@"onmouseexit"]) {
        return UDGuiEventHandlerTypeOnMouseExit;
    }
    if ([lower isEqualToString:@"onactivate"]) {
        return UDGuiEventHandlerTypeOnActivate;
    }
    if ([lower isEqualToString:@"ondeactivate"]) {
        return UDGuiEventHandlerTypeOnDeactivate;
    }
    if ([lower isEqualToString:@"onesc"]) {
        return UDGuiEventHandlerTypeOnEsc;
    }
    if ([lower isEqualToString:@"onevent"]) {
        return UDGuiEventHandlerTypeOnEvent;
    }
    if ([lower isEqualToString:@"ontrigger"]) {
        return UDGuiEventHandlerTypeOnTrigger;
    }
    if ([lower isEqualToString:@"onenter"]) {
        return UDGuiEventHandlerTypeOnEnter;
    }
    return UDGuiEventHandlerTypeOnEnterRelease;
}

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
@property (nonatomic, strong) NSMutableArray<UDIdToken *> *lookaheadTokens;
@end

@implementation UDGuiDeclCursor

- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (!self) {
        return nil;
    }

    _text = [text copy];
    _lexer = [[UDIdLexer alloc] initWithText:_text];
    _lookaheadTokens = [NSMutableArray array];
    return self;
}

- (UDIdToken *)peekToken {
    if (self.lookaheadTokens.count == 0) {
        UDIdToken *token = [self.lexer nextToken];
        if (token) {
            [self.lookaheadTokens addObject:token];
        }
    }
    return [self.lookaheadTokens firstObject];
}

- (UDIdToken *)readToken {
    if (self.lookaheadTokens.count > 0) {
        UDIdToken *token = [self.lookaheadTokens firstObject];
        [self.lookaheadTokens removeObjectAtIndex:0];
        return token;
    }
    return [self.lexer nextToken];
}

- (void)unreadToken:(UDIdToken *)token {
    if (token) {
        [self.lookaheadTokens insertObject:token atIndex:0];
    }
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

@class UDGuiDocumentCodec;

@interface UDGuiWindowEntryVisitContext : NSObject
@property (nonatomic, strong) UDGuiWindowNode *node;
@property (nonatomic, strong) UDIdToken *keyToken;
@property (nonatomic, strong) UDIdToken *secondToken;
@property (nonatomic, strong) UDGuiDeclCursor *cursor;
@property (nonatomic, assign) NSError * __autoreleasing *error;
@end

@implementation UDGuiWindowEntryVisitContext
@end

typedef BOOL (^UDGuiWindowEntryVisitBlock)(UDGuiWindowEntryVisitContext *context, UDGuiDocumentCodec *codec);

@interface UDGuiWindowEntryVisitor : NSObject
- (instancetype)initWithBlock:(UDGuiWindowEntryVisitBlock)block;
- (BOOL)visitContext:(UDGuiWindowEntryVisitContext *)context codec:(UDGuiDocumentCodec *)codec;
@end

@interface UDGuiWindowEntryVisitor ()
@property (nonatomic, copy) UDGuiWindowEntryVisitBlock block;
@end

@implementation UDGuiWindowEntryVisitor

- (instancetype)initWithBlock:(UDGuiWindowEntryVisitBlock)block {
    self = [super init];
    if (!self) {
        return nil;
    }

    _block = [block copy];
    return self;
}

- (BOOL)visitContext:(UDGuiWindowEntryVisitContext *)context codec:(UDGuiDocumentCodec *)codec {
    return self.block ? self.block(context, codec) : NO;
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
- (BOOL)isChildWindowDefinitionIdentifier:(NSString *)identifier;
- (BOOL)isEventHandlerIdentifier:(NSString *)identifier;
- (BOOL)isScriptEntryIdentifier:(NSString *)identifier;
- (NSArray<UDGuiWindowEntryVisitor *> *)windowEntryVisitors;
- (BOOL)visitChildWindowDefinitionWithContext:(UDGuiWindowEntryVisitContext *)context;
- (BOOL)visitNamedOrTimedEventWithContext:(UDGuiWindowEntryVisitContext *)context;
- (BOOL)visitVariableDefinitionWithContext:(UDGuiWindowEntryVisitContext *)context;
- (BOOL)visitScriptEntryWithContext:(UDGuiWindowEntryVisitContext *)context;
- (BOOL)visitNestedWindowFallbackWithContext:(UDGuiWindowEntryVisitContext *)context;
- (BOOL)visitBlockPropertyWithContext:(UDGuiWindowEntryVisitContext *)context;
- (BOOL)visitScalarPropertyWithContext:(UDGuiWindowEntryVisitContext *)context;
- (nullable UDGuiEventHandler *)parseEventHandlerForKeyToken:(UDIdToken *)keyToken
                                                  secondToken:(UDIdToken *)secondToken
                                                       cursor:(UDGuiDeclCursor *)cursor
                                                        error:(NSError **)error;
- (NSArray<NSString *> *)scriptStatementsFromBlockValue:(NSString *)blockValue;
- (nullable NSArray<UDGuiScriptCommand *> *)scriptCommandsFromBlockValue:(NSString *)blockValue;
- (nullable NSArray<UDGuiScriptCommand *> *)parseScriptCommandsWithCursor:(UDGuiDeclCursor *)cursor stopAtCloseBrace:(BOOL)stopAtCloseBrace;
- (nullable UDGuiScriptCommand *)parseIfCommandWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable UDGuiExpression *)parseExpressionWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable UDGuiExpression *)parseLogicalOrExpressionWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable UDGuiExpression *)parseLogicalAndExpressionWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable UDGuiExpression *)parseEqualityExpressionWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable UDGuiExpression *)parseRelationalExpressionWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable UDGuiExpression *)parseAdditiveExpressionWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable UDGuiExpression *)parseMultiplicativeExpressionWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable UDGuiExpression *)parseUnaryExpressionWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable UDGuiExpression *)parsePrimaryExpressionWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable NSString *)peekOperatorWithCursor:(UDGuiDeclCursor *)cursor;
- (nullable NSString *)readOperatorWithCursor:(UDGuiDeclCursor *)cursor expected:(NSArray<NSString *> *)expectedOps;
- (NSString *)rawScriptBodyFromBlockValue:(NSString *)blockValue;
- (NSString *)normalizedRawScriptBodyFromBlockValue:(NSString *)blockValue;
- (NSString *)normalizedRawScriptTokenText:(UDIdToken *)token;
- (UDGuiScriptCommand *)scriptCommandFromStatement:(NSString *)statement;
- (UDGuiScriptCommand *)scriptCommandWithKeyword:(NSString *)keyword arguments:(NSString *)arguments;
- (NSString *)serializedScriptBlockForEventHandler:(UDGuiEventHandler *)eventHandler indent:(NSString *)indent;
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
    UDGuiDeclCursor *cursor = [[UDGuiDeclCursor alloc] initWithText:text ?: @""];

    while (YES) {
        UDIdToken *token = [cursor readToken];
        if (token.kind == UDIdTokenKindEOF) {
            break;
        }

        if (token.kind != UDIdTokenKindIdentifier && token.kind != UDIdTokenKindString) {
            continue;
        }

        if (![self isChildWindowDefinitionIdentifier:token.text]) {
            continue;
        }

        UDIdToken *nameToken = [cursor readToken];
        if (nameToken.kind == UDIdTokenKindEOF) {
            if (error) {
                *error = [NSError errorWithDomain:UDGuiDocumentCodecErrorDomain
                                             code:UDGuiDocumentCodecErrorCodeUnexpectedEOF
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unexpected EOF while reading top-level window name."}];
            }
            return nil;
        }

        UDIdToken *openBrace = [cursor readToken];
        if (openBrace.kind != UDIdTokenKindPunctuation || ![openBrace.text isEqualToString:@"{"]) {
            continue;
        }

        UDGuiWindowNode *window = [self parseWindowBodyWithClassName:token.text
                                                                 name:nameToken.text
                                                               cursor:cursor
                                                                error:error];
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
    if ([className.lowercaseString isEqualToString:@"animationdef"]) {
        // Match Doom behavior: default hidden/zero-sized before parsing, allow parsed values to override.
        node.visible = NO;
        [node setPropertyValue:@"0, 0, 0, 0" forKey:@"rect"];
    }
    NSArray<UDGuiWindowEntryVisitor *> *visitors = [self windowEntryVisitors];

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
            // Script-entry handlers (`onAction`, `onEvent`, etc.) also start with '{'.
            // Let the visitor chain classify those first; otherwise treat as plain block property.
            if (![self isScriptEntryIdentifier:keyOrClassToken.text]) {
                NSString *blockValue = [self parseBlockValueStartingWithToken:secondToken cursor:cursor error:error];
                if (!blockValue) {
                    return nil;
                }
                [node setPropertyValue:blockValue forKey:keyOrClassToken.text ?: @""];
                continue;
            }
        }

        UDGuiWindowEntryVisitContext *context = [[UDGuiWindowEntryVisitContext alloc] init];
        context.node = node;
        context.keyToken = keyOrClassToken;
        context.secondToken = secondToken;
        context.cursor = cursor;
        context.error = error;

        BOOL handled = NO;
        for (UDGuiWindowEntryVisitor *visitor in visitors) {
            if ([visitor visitContext:context codec:self]) {
                handled = YES;
                break;
            }
        }

        if (!handled) {
            [self visitScalarPropertyWithContext:context];
        }

        if (error && *error) {
            return nil;
        }
    }

    return node;
}

- (NSArray<UDGuiWindowEntryVisitor *> *)windowEntryVisitors {
    return @[
        [[UDGuiWindowEntryVisitor alloc] initWithBlock:^BOOL(UDGuiWindowEntryVisitContext *context, UDGuiDocumentCodec *codec) {
            return [codec visitChildWindowDefinitionWithContext:context];
        }],
        [[UDGuiWindowEntryVisitor alloc] initWithBlock:^BOOL(UDGuiWindowEntryVisitContext *context, UDGuiDocumentCodec *codec) {
            return [codec visitNamedOrTimedEventWithContext:context];
        }],
        [[UDGuiWindowEntryVisitor alloc] initWithBlock:^BOOL(UDGuiWindowEntryVisitContext *context, UDGuiDocumentCodec *codec) {
            return [codec visitVariableDefinitionWithContext:context];
        }],
        [[UDGuiWindowEntryVisitor alloc] initWithBlock:^BOOL(UDGuiWindowEntryVisitContext *context, UDGuiDocumentCodec *codec) {
            return [codec visitScriptEntryWithContext:context];
        }],
        [[UDGuiWindowEntryVisitor alloc] initWithBlock:^BOOL(UDGuiWindowEntryVisitContext *context, UDGuiDocumentCodec *codec) {
            return [codec visitNestedWindowFallbackWithContext:context];
        }],
        [[UDGuiWindowEntryVisitor alloc] initWithBlock:^BOOL(UDGuiWindowEntryVisitContext *context, UDGuiDocumentCodec *codec) {
            return [codec visitBlockPropertyWithContext:context];
        }],
    ];
}

- (BOOL)visitChildWindowDefinitionWithContext:(UDGuiWindowEntryVisitContext *)context {
    UDIdToken *keyOrClassToken = context.keyToken;
    UDIdToken *secondToken = context.secondToken;
    UDGuiDeclCursor *cursor = context.cursor;

    if (![self isChildWindowDefinitionIdentifier:keyOrClassToken.text] ||
        (secondToken.kind != UDIdTokenKindIdentifier && secondToken.kind != UDIdTokenKindString)) {
        return NO;
    }

    UDIdToken *thirdToken = [cursor peekToken];
    if (thirdToken.kind != UDIdTokenKindPunctuation || ![thirdToken.text isEqualToString:@"{"]) {
        return NO;
    }

    (void)[cursor readToken];
    UDGuiWindowNode *child = [self parseWindowBodyWithClassName:keyOrClassToken.text
                                                            name:secondToken.text
                                                          cursor:cursor
                                                           error:context.error];
    if (!child) {
        return YES;
    }

    [context.node addChild:child];
    return YES;
}

- (BOOL)visitNamedOrTimedEventWithContext:(UDGuiWindowEntryVisitContext *)context {
    NSString *lower = (context.keyToken.text ?: @"").lowercaseString;
    if (![lower isEqualToString:@"onnamedevent"] && ![lower isEqualToString:@"ontime"]) {
        return NO;
    }

    UDGuiEventHandler *eventHandler = [self parseEventHandlerForKeyToken:context.keyToken
                                                              secondToken:context.secondToken
                                                                   cursor:context.cursor
                                                                    error:context.error];
    if (!eventHandler) {
        return YES;
    }

    [context.node addEventHandler:eventHandler];
    return YES;
}

- (BOOL)visitVariableDefinitionWithContext:(UDGuiWindowEntryVisitContext *)context {
    NSString *key = context.keyToken.text ?: @"";
    if ([key caseInsensitiveCompare:@"definefloat"] != NSOrderedSame &&
        [key caseInsensitiveCompare:@"float"] != NSOrderedSame &&
        [key caseInsensitiveCompare:@"definevec4"] != NSOrderedSame) {
        return NO;
    }

    UDGuiDeclCursor *cursor = context.cursor;
    UDIdToken *secondToken = context.secondToken;
    NSString *variableName = secondToken.text ?: @"";
    UDIdToken *firstValueToken = nil;
    UDIdToken *lastValueToken = nil;
    BOOL consumedValueToken = NO;
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

        UDIdToken *consumed = [cursor readToken];
        if (!firstValueToken) {
            firstValueToken = consumed;
        }
        consumedValueToken = YES;
        lastValueToken = consumed;
    }
    NSString *variableValue = @"";
    if (consumedValueToken) {
        variableValue = [[cursor sourceSliceFromToken:firstValueToken toToken:lastValueToken]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    UDGuiVariableDefinitionType type = [key caseInsensitiveCompare:@"definevec4"] == NSOrderedSame
        ? UDGuiVariableDefinitionTypeVec4
        : UDGuiVariableDefinitionTypeFloat;
    [context.node addVariableDefinition:[[UDGuiVariableDefinition alloc] initWithType:type
                                                                         name:variableName
                                                                        value:variableValue]];
    return YES;
}

- (BOOL)visitScriptEntryWithContext:(UDGuiWindowEntryVisitContext *)context {
    if (![self isScriptEntryIdentifier:context.keyToken.text]) {
        return NO;
    }

    UDGuiEventHandler *eventHandler = [self parseEventHandlerForKeyToken:context.keyToken
                                                              secondToken:context.secondToken
                                                                   cursor:context.cursor
                                                                    error:context.error];
    if (!eventHandler) {
        return YES;
    }

    [context.node addEventHandler:eventHandler];
    return YES;
}

- (BOOL)visitNestedWindowFallbackWithContext:(UDGuiWindowEntryVisitContext *)context {
    UDIdToken *thirdToken = [context.cursor peekToken];
    if (thirdToken.kind != UDIdTokenKindPunctuation || ![thirdToken.text isEqualToString:@"{"] ||
        ![self isWindowClassIdentifier:context.keyToken.text]) {
        return NO;
    }

    (void)[context.cursor readToken];
    UDGuiWindowNode *child = [self parseWindowBodyWithClassName:context.keyToken.text
                                                            name:context.secondToken.text
                                                          cursor:context.cursor
                                                           error:context.error];
    if (!child) {
        return YES;
    }

    [context.node addChild:child];
    return YES;
}

- (BOOL)visitBlockPropertyWithContext:(UDGuiWindowEntryVisitContext *)context {
    UDIdToken *thirdToken = [context.cursor peekToken];
    if (thirdToken.kind != UDIdTokenKindPunctuation || ![thirdToken.text isEqualToString:@"{"]) {
        return NO;
    }

    (void)[context.cursor readToken];
    NSString *blockValue = [self parseBlockValueStartingWithToken:thirdToken cursor:context.cursor error:context.error];
    if (!blockValue) {
        return YES;
    }

    NSString *fullValue = [NSString stringWithFormat:@"%@ %@",
                           [context.cursor sourceSliceFromToken:context.secondToken toToken:context.secondToken],
                           blockValue];
    [context.node setPropertyValue:[fullValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                            forKey:context.keyToken.text ?: @""];
    return YES;
}

- (BOOL)visitScalarPropertyWithContext:(UDGuiWindowEntryVisitContext *)context {
    UDIdToken *lastValueToken = context.secondToken;
    while (YES) {
        UDIdToken *valueToken = [context.cursor peekToken];
        if (valueToken.kind == UDIdTokenKindEOF) {
            break;
        }
        if (valueToken.kind == UDIdTokenKindPunctuation && [valueToken.text isEqualToString:@"}"]) {
            break;
        }
        if ([context.cursor containsNewlineBetweenToken:lastValueToken andToken:valueToken]) {
            break;
        }
        lastValueToken = [context.cursor readToken];
    }

    NSString *value = nil;
    if (context.secondToken == lastValueToken && context.secondToken.kind == UDIdTokenKindString) {
        value = context.secondToken.text ?: @"";
    } else {
        value = [[context.cursor sourceSliceFromToken:context.secondToken toToken:lastValueToken]
                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    [context.node setPropertyValue:value forKey:context.keyToken.text ?: @""];
    return YES;
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

- (BOOL)isChildWindowDefinitionIdentifier:(NSString *)identifier {
    NSString *lower = identifier.lowercaseString;
    static NSSet<NSString *> *definitionKeys = nil;
    @synchronized([self class]) {
        if (definitionKeys == nil) {
            definitionKeys = [NSSet setWithObjects:
                @"windowdef",
                @"animationdef",
                @"editdef",
                @"choicedef",
                @"sliderdef",
                @"markerdef",
                @"binddef",
                @"listdef",
                @"fielddef",
                @"renderdef",
                @"gamessddef",
                @"gamebearshootdef",
                @"gamebustoutdef",
                nil];
        }
    }

    return [definitionKeys containsObject:lower];
}

- (BOOL)isEventHandlerIdentifier:(NSString *)identifier {
    NSString *lower = identifier.lowercaseString;
    static NSSet<NSString *> *eventKeys = nil;
    @synchronized([self class]) {
        if (eventKeys == nil) {
            eventKeys = [NSSet setWithObjects:
                @"ontime",
                @"onnamedevent",
                @"onaction",
                @"onactionrelease",
                @"onmouseenter",
                @"onmouseexit",
                @"onactivate",
                @"ondeactivate",
                @"onesc",
                @"onevent",
                @"ontrigger",
                @"onenter",
                @"onenterrelease",
                nil];
        }
    }

    return [eventKeys containsObject:lower];
}

- (BOOL)isScriptEntryIdentifier:(NSString *)identifier {
    NSString *lower = identifier.lowercaseString;
    static NSSet<NSString *> *scriptEntryKeys = nil;
    @synchronized([self class]) {
        if (scriptEntryKeys == nil) {
            scriptEntryKeys = [NSSet setWithObjects:
                @"onaction",
                @"onactionrelease",
                @"onmouseenter",
                @"onmouseexit",
                @"onactivate",
                @"ondeactivate",
                @"onesc",
                @"onevent",
                @"ontrigger",
                @"onenter",
                @"onenterrelease",
                nil];
        }
    }

    return [scriptEntryKeys containsObject:lower];
}

- (nullable UDGuiEventHandler *)parseEventHandlerForKeyToken:(UDIdToken *)keyToken
                                                  secondToken:(UDIdToken *)secondToken
                                                       cursor:(UDGuiDeclCursor *)cursor
                                                        error:(NSError **)error {
    NSString *key = keyToken.text ?: @"";
    NSString *lower = key.lowercaseString;
    UDIdToken *openBraceToken = nil;
    UDGuiEventHandler *handler = nil;

    if ([lower isEqualToString:@"ontime"]) {
        NSString *timeExpression = secondToken.text ?: @"0";
        openBraceToken = [cursor readToken];
        if (openBraceToken.kind != UDIdTokenKindPunctuation || ![openBraceToken.text isEqualToString:@"{"]) {
            if (error) {
                *error = [NSError errorWithDomain:UDGuiDocumentCodecErrorDomain
                                             code:UDGuiDocumentCodecErrorCodeUnexpectedToken
                                         userInfo:@{NSLocalizedDescriptionKey: @"Expected '{' after onTime <time>."}];
            }
            return nil;
        }
        handler = [[UDGuiTimedEventHandler alloc] initWithTimeExpression:timeExpression];
    } else if ([lower isEqualToString:@"onnamedevent"]) {
        NSString *eventName = secondToken.text ?: @"";
        openBraceToken = [cursor readToken];
        if (openBraceToken.kind != UDIdTokenKindPunctuation || ![openBraceToken.text isEqualToString:@"{"]) {
            if (error) {
                *error = [NSError errorWithDomain:UDGuiDocumentCodecErrorDomain
                                             code:UDGuiDocumentCodecErrorCodeUnexpectedToken
                                         userInfo:@{NSLocalizedDescriptionKey: @"Expected '{' after onNamedEvent <event>."}];
            }
            return nil;
        }
        handler = [[UDGuiNamedEventHandler alloc] initWithEventName:eventName];
    } else {
        if (secondToken.kind != UDIdTokenKindPunctuation || ![secondToken.text isEqualToString:@"{"]) {
            if (error) {
                *error = [NSError errorWithDomain:UDGuiDocumentCodecErrorDomain
                                             code:UDGuiDocumentCodecErrorCodeUnexpectedToken
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Expected '{' after %@.", key]}];
            }
            return nil;
        }
        openBraceToken = secondToken;
        handler = [[UDGuiSimpleEventHandler alloc] initWithType:UDGuiEventHandlerTypeForIdentifier(key)];
    }

    NSString *blockValue = [self parseBlockValueStartingWithToken:openBraceToken cursor:cursor error:error];
    if (!blockValue) {
        return nil;
    }

    NSArray<UDGuiScriptCommand *> *commands = [self scriptCommandsFromBlockValue:blockValue];
    if (!commands) {
        [handler addCommand:[[UDGuiScriptCommand alloc] initWithKeyword:UDGuiRawScriptBodyCommandKeyword
                                                               arguments:[self normalizedRawScriptBodyFromBlockValue:blockValue]]];
        return handler;
    }

    for (UDGuiScriptCommand *command in commands) {
        [handler addCommand:command];
    }

    return handler;
}

- (nullable NSArray<UDGuiScriptCommand *> *)scriptCommandsFromBlockValue:(NSString *)blockValue {
    return [self scriptCommandsFromBlockValue:blockValue error:nil];
}

- (nullable NSArray<UDGuiScriptCommand *> *)scriptCommandsFromBlockValue:(NSString *)blockValue error:(NSError **)error {
    NSString *inner = [self rawScriptBodyFromBlockValue:blockValue];
    if (inner.length == 0) {
        return @[];
    }

    UDGuiDeclCursor *cursor = [[UDGuiDeclCursor alloc] initWithText:inner];
    NSArray<UDGuiScriptCommand *> *commands = [self parseScriptCommandsWithCursor:cursor stopAtCloseBrace:NO];
    if (!commands) {
        UDIdToken *lastToken = [cursor peekToken];
        NSUInteger offset = lastToken ? lastToken.start : inner.length;
        if (error) {
            NSString *msg = [NSString stringWithFormat:@"Syntax error near '%@' at character offset %lu. Expected a valid command or end of script.", lastToken ? lastToken.text : @"EOF", (unsigned long)offset];
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: msg,
                @"characterOffset": @(offset),
                @"tokenText": lastToken ? (lastToken.text ?: @"") : @""
            };
            *error = [NSError errorWithDomain:@"com.udquake.error.scripteditor"
                                         code:1
                                     userInfo:userInfo];
        }
        return nil;
    }
    return commands;
}

- (nullable NSArray<UDGuiScriptCommand *> *)parseScriptCommandsWithCursor:(UDGuiDeclCursor *)cursor stopAtCloseBrace:(BOOL)stopAtCloseBrace {
    NSMutableArray<UDGuiScriptCommand *> *commands = [NSMutableArray array];

    while (YES) {
        UDIdToken *token = [cursor readToken];
        if (token.kind == UDIdTokenKindEOF) {
            if (stopAtCloseBrace) {
                NSLog(@"UDGuiDocumentCodec: Parsing script commands failed: reached EOF without matching close brace. Expected closing brace at character offset %lu.", (unsigned long)token.start);
                return nil; // Unmatched open brace
            }
            break;
        }

        if (token.kind == UDIdTokenKindPunctuation) {
            if ([token.text isEqualToString:@";"]) {
                continue;
            }
            if ([token.text isEqualToString:@"}"] && stopAtCloseBrace) {
                break;
            }
        }

        if (token.kind == UDIdTokenKindIdentifier && [token.text caseInsensitiveCompare:@"if"] == NSOrderedSame) {
            UDGuiScriptCommand *ifCmd = [self parseIfCommandWithCursor:cursor];
            if (!ifCmd) {
                return nil;
            }
            [commands addObject:ifCmd];
            continue;
        }

        if (token.kind != UDIdTokenKindIdentifier && token.kind != UDIdTokenKindString) {
            return nil;
        }

        NSString *keyword = token.text ?: @"";
        NSMutableArray<NSString *> *arguments = [NSMutableArray array];

        while (YES) {
            UDIdToken *argToken = [cursor readToken];
            if (argToken.kind == UDIdTokenKindEOF) {
                break;
            }
            if (argToken.kind == UDIdTokenKindPunctuation) {
                if ([argToken.text isEqualToString:@";"]) {
                    break;
                }
                if ([argToken.text isEqualToString:@"{"] || [argToken.text isEqualToString:@"}"]) {
                    [cursor unreadToken:argToken];
                    break;
                }
            }
            if (argToken.kind == UDIdTokenKindIdentifier && [argToken.text caseInsensitiveCompare:@"if"] == NSOrderedSame) {
                [cursor unreadToken:argToken];
                break;
            }

            if (argToken.text.length > 0) {
                [arguments addObject:argToken.text];
            }
        }

        [commands addObject:[self scriptCommandWithKeyword:keyword arguments:[arguments componentsJoinedByString:@" "]]];
    }

    return [commands copy];
}

- (nullable UDGuiScriptCommand *)parseIfCommandWithCursor:(UDGuiDeclCursor *)cursor {
    NSMutableArray<UDGuiIfBranch *> *branches = [NSMutableArray array];

    UDIdToken *openParen = [cursor readToken];
    if (openParen.kind != UDIdTokenKindPunctuation || ![openParen.text isEqualToString:@"("]) {
        return nil;
    }
    UDGuiExpression *condition = [self parseExpressionWithCursor:cursor];
    if (!condition) {
        return nil;
    }
    UDIdToken *closeParen = [cursor readToken];
    if (closeParen.kind != UDIdTokenKindPunctuation || ![closeParen.text isEqualToString:@")"]) {
        return nil;
    }

    UDIdToken *openBrace = [cursor readToken];
    if (openBrace.kind != UDIdTokenKindPunctuation || ![openBrace.text isEqualToString:@"{"]) {
        return nil;
    }
    NSArray<UDGuiScriptCommand *> *thenCommands = [self parseScriptCommandsWithCursor:cursor stopAtCloseBrace:YES];
    if (!thenCommands) {
        return nil;
    }
    [branches addObject:[[UDGuiIfBranch alloc] initWithCondition:condition commands:thenCommands]];

    while (YES) {
        UDIdToken *elseToken = [cursor readToken];
        if (elseToken.kind == UDIdTokenKindIdentifier && [elseToken.text caseInsensitiveCompare:@"else"] == NSOrderedSame) {
            UDIdToken *nextToken = [cursor readToken];
            if (nextToken.kind == UDIdTokenKindIdentifier && [nextToken.text caseInsensitiveCompare:@"if"] == NSOrderedSame) {
                UDIdToken *elseOpenParen = [cursor readToken];
                if (elseOpenParen.kind != UDIdTokenKindPunctuation || ![elseOpenParen.text isEqualToString:@"("]) {
                    return nil;
                }
                UDGuiExpression *elseCondition = [self parseExpressionWithCursor:cursor];
                if (!elseCondition) {
                    return nil;
                }
                UDIdToken *elseCloseParen = [cursor readToken];
                if (elseCloseParen.kind != UDIdTokenKindPunctuation || ![elseCloseParen.text isEqualToString:@")"]) {
                    return nil;
                }
                UDIdToken *elseOpenBrace = [cursor readToken];
                if (elseOpenBrace.kind != UDIdTokenKindPunctuation || ![elseOpenBrace.text isEqualToString:@"{"]) {
                    return nil;
                }
                NSArray<UDGuiScriptCommand *> *elseIfCommands = [self parseScriptCommandsWithCursor:cursor stopAtCloseBrace:YES];
                if (!elseIfCommands) {
                    return nil;
                }
                [branches addObject:[[UDGuiIfBranch alloc] initWithCondition:elseCondition commands:elseIfCommands]];
            } else if (nextToken.kind == UDIdTokenKindPunctuation && [nextToken.text isEqualToString:@"{"]) {
                NSArray<UDGuiScriptCommand *> *elseCommands = [self parseScriptCommandsWithCursor:cursor stopAtCloseBrace:YES];
                if (!elseCommands) {
                    return nil;
                }
                [branches addObject:[[UDGuiIfBranch alloc] initWithCondition:nil commands:elseCommands]];
                break;
            } else {
                return nil;
            }
        } else {
            if (elseToken.kind != UDIdTokenKindEOF) {
                [cursor unreadToken:elseToken];
            }
            break;
        }
    }

    return [[UDGuiIfCommand alloc] initWithBranches:branches];
}

- (nullable UDGuiExpression *)parseExpressionWithCursor:(UDGuiDeclCursor *)cursor {
    return [self parseLogicalOrExpressionWithCursor:cursor];
}

- (nullable UDGuiExpression *)parseLogicalOrExpressionWithCursor:(UDGuiDeclCursor *)cursor {
    UDGuiExpression *left = [self parseLogicalAndExpressionWithCursor:cursor];
    if (!left) return nil;

    while (YES) {
        NSString *op = [self readOperatorWithCursor:cursor expected:@[@"||"]];
        if (!op) break;
        UDGuiExpression *right = [self parseLogicalAndExpressionWithCursor:cursor];
        if (!right) return nil;
        left = [[UDGuiBinaryExpression alloc] initWithLeft:left operator:op right:right];
    }
    return left;
}

- (nullable UDGuiExpression *)parseLogicalAndExpressionWithCursor:(UDGuiDeclCursor *)cursor {
    UDGuiExpression *left = [self parseEqualityExpressionWithCursor:cursor];
    if (!left) return nil;

    while (YES) {
        NSString *op = [self readOperatorWithCursor:cursor expected:@[@"&&"]];
        if (!op) break;
        UDGuiExpression *right = [self parseEqualityExpressionWithCursor:cursor];
        if (!right) return nil;
        left = [[UDGuiBinaryExpression alloc] initWithLeft:left operator:op right:right];
    }
    return left;
}

- (nullable UDGuiExpression *)parseEqualityExpressionWithCursor:(UDGuiDeclCursor *)cursor {
    UDGuiExpression *left = [self parseRelationalExpressionWithCursor:cursor];
    if (!left) return nil;

    while (YES) {
        NSString *op = [self readOperatorWithCursor:cursor expected:@[@"==", @"!="]];
        if (!op) break;
        UDGuiExpression *right = [self parseRelationalExpressionWithCursor:cursor];
        if (!right) return nil;
        left = [[UDGuiBinaryExpression alloc] initWithLeft:left operator:op right:right];
    }
    return left;
}

- (nullable UDGuiExpression *)parseRelationalExpressionWithCursor:(UDGuiDeclCursor *)cursor {
    UDGuiExpression *left = [self parseAdditiveExpressionWithCursor:cursor];
    if (!left) return nil;

    while (YES) {
        NSString *op = [self readOperatorWithCursor:cursor expected:@[@"<", @"<=", @">", @">="]];
        if (!op) break;
        UDGuiExpression *right = [self parseAdditiveExpressionWithCursor:cursor];
        if (!right) return nil;
        left = [[UDGuiBinaryExpression alloc] initWithLeft:left operator:op right:right];
    }
    return left;
}

- (nullable UDGuiExpression *)parseAdditiveExpressionWithCursor:(UDGuiDeclCursor *)cursor {
    UDGuiExpression *left = [self parseMultiplicativeExpressionWithCursor:cursor];
    if (!left) return nil;

    while (YES) {
        NSString *op = [self readOperatorWithCursor:cursor expected:@[@"+", @"-"]];
        if (!op) break;
        UDGuiExpression *right = [self parseMultiplicativeExpressionWithCursor:cursor];
        if (!right) return nil;
        left = [[UDGuiBinaryExpression alloc] initWithLeft:left operator:op right:right];
    }
    return left;
}

- (nullable UDGuiExpression *)parseMultiplicativeExpressionWithCursor:(UDGuiDeclCursor *)cursor {
    UDGuiExpression *left = [self parseUnaryExpressionWithCursor:cursor];
    if (!left) return nil;

    while (YES) {
        NSString *op = [self readOperatorWithCursor:cursor expected:@[@"*", @"/"]];
        if (!op) break;
        UDGuiExpression *right = [self parseUnaryExpressionWithCursor:cursor];
        if (!right) return nil;
        left = [[UDGuiBinaryExpression alloc] initWithLeft:left operator:op right:right];
    }
    return left;
}

- (nullable UDGuiExpression *)parseUnaryExpressionWithCursor:(UDGuiDeclCursor *)cursor {
    UDIdToken *token = [cursor readToken];
    if (token.kind == UDIdTokenKindPunctuation && ([token.text isEqualToString:@"!"] || [token.text isEqualToString:@"-"])) {
        NSString *op = token.text;
        UDGuiExpression *operand = [self parseUnaryExpressionWithCursor:cursor];
        if (!operand) {
            return nil;
        }
        return [[UDGuiUnaryExpression alloc] initWithOperator:op operand:operand];
    }

    if (token.kind != UDIdTokenKindEOF) {
        [cursor unreadToken:token];
    }
    return [self parsePrimaryExpressionWithCursor:cursor];
}

- (nullable UDGuiExpression *)parsePrimaryExpressionWithCursor:(UDGuiDeclCursor *)cursor {
    UDIdToken *token = [cursor readToken];
    if (token.kind == UDIdTokenKindEOF) {
        return nil;
    }

    if (token.kind == UDIdTokenKindPunctuation && [token.text isEqualToString:@"("]) {
        UDGuiExpression *inner = [self parseExpressionWithCursor:cursor];
        if (!inner) {
            return nil;
        }
        UDIdToken *close = [cursor readToken];
        if (close.kind != UDIdTokenKindPunctuation || ![close.text isEqualToString:@")"]) {
            return nil;
        }
        return [[UDGuiParenthesizedExpression alloc] initWithExpression:inner];
    }

    if (token.kind == UDIdTokenKindString) {
        BOOL isVariable = NO;
        if (token.text.length > 0) {
            if ([token.text rangeOfString:@"::"].location != NSNotFound) {
                isVariable = YES;
            } else {
                static NSCharacterSet *disallowedSet = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    // Allowed characters for variables/properties include alphanumeric characters,
                    // underscores, colons (for namespace qualifiers), and periods (for property references).
                    NSMutableCharacterSet *allowedSet = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
                    [allowedSet addCharactersInString:@"_:."];
                    disallowedSet = [allowedSet invertedSet];
                });
                if ([token.text rangeOfCharacterFromSet:disallowedSet].location == NSNotFound) {
                    isVariable = YES;
                }
            }
        }
        if (isVariable) {
            return [[UDGuiVariableExpression alloc] initWithName:token.text];
        }
        return [[UDGuiStringLiteralExpression alloc] initWithValue:token.text];
    }

    if (token.kind == UDIdTokenKindIdentifier) {
        NSScanner *scanner = [NSScanner scannerWithString:token.text];
        double dVal;
        // Check if token.text is a numeric literal
        if ([scanner scanDouble:&dVal] && scanner.isAtEnd) {
            return [[UDGuiNumberLiteralExpression alloc] initWithValue:token.text];
        }
        return [[UDGuiVariableExpression alloc] initWithName:token.text];
    }

    if (token.kind != UDIdTokenKindEOF) {
        [cursor unreadToken:token];
    }
    return nil;
}

- (nullable NSString *)peekOperatorWithCursor:(UDGuiDeclCursor *)cursor {
    UDIdToken *first = [cursor readToken];
    if (first.kind != UDIdTokenKindPunctuation) {
        if (first.kind != UDIdTokenKindEOF) {
            [cursor unreadToken:first];
        }
        return nil;
    }

    NSString *op = first.text;
    UDIdToken *second = [cursor readToken];
    NSString *combined = nil;
    if (second.kind == UDIdTokenKindPunctuation) {
        if ([op isEqualToString:@"="] && [second.text isEqualToString:@"="]) combined = @"==";
        else if ([op isEqualToString:@"!"] && [second.text isEqualToString:@"="]) combined = @"!=";
        else if ([op isEqualToString:@"<"] && [second.text isEqualToString:@"="]) combined = @"<=";
        else if ([op isEqualToString:@">"] && [second.text isEqualToString:@"="]) combined = @">=";
        else if ([op isEqualToString:@"&"] && [second.text isEqualToString:@"&"]) combined = @"&&";
        else if ([op isEqualToString:@"|"] && [second.text isEqualToString:@"|"]) combined = @"||";
    }

    if (second.kind != UDIdTokenKindEOF) {
        [cursor unreadToken:second];
    }
    if (first.kind != UDIdTokenKindEOF) {
        [cursor unreadToken:first];
    }

    if (combined) {
        return combined;
    }

    if ([op isEqualToString:@"+"] || [op isEqualToString:@"-"] || [op isEqualToString:@"*"] ||
        [op isEqualToString:@"/"] || [op isEqualToString:@"<"] || [op isEqualToString:@">"]) {
        return op;
    }

    return nil;
}

- (nullable NSString *)readOperatorWithCursor:(UDGuiDeclCursor *)cursor expected:(NSArray<NSString *> *)expectedOps {
    NSString *peeked = [self peekOperatorWithCursor:cursor];
    if (!peeked || ![expectedOps containsObject:peeked]) {
        return nil;
    }

    [cursor readToken];
    if (peeked.length == 2) {
        [cursor readToken];
    }
    return peeked;
}

- (NSString *)rawScriptBodyFromBlockValue:(NSString *)blockValue {
    if (blockValue.length == 0) {
        return @"";
    }

    NSString *inner = [blockValue copy];
    if ([inner hasPrefix:@"{"] && [inner hasSuffix:@"}"] && inner.length >= 2) {
        inner = [inner substringWithRange:NSMakeRange(1, inner.length - 2)];
    }

    return [inner stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)normalizedRawScriptBodyFromBlockValue:(NSString *)blockValue {
    NSString *inner = [self rawScriptBodyFromBlockValue:blockValue];
    if (inner.length == 0) {
        return @"";
    }

    UDGuiDeclCursor *cursor = [[UDGuiDeclCursor alloc] initWithText:inner];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    while (YES) {
        UDIdToken *token = [cursor readToken];
        if (token.kind == UDIdTokenKindEOF) {
            break;
        }
        if (token.text.length == 0) {
            continue;
        }
        [parts addObject:[self normalizedRawScriptTokenText:token]];
    }

    // Rebuild common two-character operators split by the lexer punctuation pass.
    NSMutableArray<NSString *> *collapsed = [NSMutableArray array];
    for (NSUInteger idx = 0; idx < parts.count; idx++) {
        NSString *current = [parts objectAtIndex:idx];
        NSString *next = (idx + 1) < parts.count ? [parts objectAtIndex:(idx + 1)] : nil;

        if (next) {
            NSString *pair = [NSString stringWithFormat:@"%@ %@", current, next];
            NSString *combined = nil;
            if ([pair isEqualToString:@"= ="]) {
                combined = @"==";
            } else if ([pair isEqualToString:@"! ="]) {
                combined = @"!=";
            } else if ([pair isEqualToString:@"< ="]) {
                combined = @"<=";
            } else if ([pair isEqualToString:@"> ="]) {
                combined = @">=";
            } else if ([pair isEqualToString:@"& &"]) {
                combined = @"&&";
            } else if ([pair isEqualToString:@"| |"]) {
                combined = @"||";
            }

            if (combined) {
                [collapsed addObject:combined];
                idx++;
                continue;
            }
        }

        [collapsed addObject:current];
    }

    NSString *normalized = [[collapsed componentsJoinedByString:@" "]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [normalized stringByReplacingOccurrencesOfString:@"\"" withString:@""];
}

- (NSString *)normalizedRawScriptTokenText:(UDIdToken *)token {
    if (token.kind == UDIdTokenKindString) {
        NSString *text = token.text ?: @"";
        if ([text hasPrefix:@"\""] && [text hasSuffix:@"\""] && text.length >= 2) {
            return [text substringWithRange:NSMakeRange(1, text.length - 2)];
        }
        return text;
    }

    return token.text ?: @"";
}

- (NSArray<NSString *> *)scriptStatementsFromBlockValue:(NSString *)blockValue {
    if (blockValue.length == 0) {
        return @[];
    }

    NSString *inner = [blockValue copy];
    if ([inner hasPrefix:@"{"] && [inner hasSuffix:@"}"] && inner.length >= 2) {
        inner = [inner substringWithRange:NSMakeRange(1, inner.length - 2)];
    }

    NSMutableArray<NSString *> *statements = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL inString = NO;
    unichar previous = 0;
    for (NSUInteger idx = 0; idx < inner.length; idx++) {
        unichar ch = [inner characterAtIndex:idx];
        if (ch == '"' && previous != '\\') {
            inString = !inString;
        }

        if (ch == ';' && !inString) {
            NSString *statement = [current stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (statement.length > 0) {
                [statements addObject:statement];
            }
            [current setString:@""];
            previous = ch;
            continue;
        }

        [current appendFormat:@"%C", ch];
        previous = ch;
    }

    NSString *tail = [current stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (tail.length > 0) {
        [statements addObject:tail];
    }

    return [statements copy];
}

- (UDGuiScriptCommand *)scriptCommandFromStatement:(NSString *)statement {
    NSString *trimmed = [statement stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return [[UDGuiScriptCommand alloc] initWithKeyword:@"evalRegs" arguments:@""];
    }

    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    NSString *keyword = nil;
    if (![scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&keyword] || keyword.length == 0) {
        return [[UDGuiScriptCommand alloc] initWithKeyword:trimmed arguments:@""];
    }

    NSString *arguments = @"";
    if (!scanner.isAtEnd) {
        arguments = [[trimmed substringFromIndex:scanner.scanLocation]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    return [self scriptCommandWithKeyword:keyword arguments:arguments];
}

- (UDGuiScriptCommand *)scriptCommandWithKeyword:(NSString *)keyword arguments:(NSString *)arguments {
    NSString *lower = keyword.lowercaseString;
    NSArray<NSString *> *parts = [[arguments stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) {
            [tokens addObject:part];
        }
    }

    if ([lower isEqualToString:@"set"] && tokens.count > 0) {
        NSString *variable = [tokens objectAtIndex:0];
        NSString *valueExpression = tokens.count > 1 ? [[tokens subarrayWithRange:NSMakeRange(1, tokens.count - 1)] componentsJoinedByString:@" "] : @"";
        return [[UDGuiSetCommand alloc] initWithVariable:variable valueExpression:valueExpression];
    }

    if ([lower isEqualToString:@"setfocus"] && tokens.count > 0) {
        return [[UDGuiSetFocusCommand alloc] initWithWindowName:[tokens objectAtIndex:0]];
    }

    if ([lower isEqualToString:@"resettime"]) {
        NSString *windowName = tokens.count > 0 ? [tokens objectAtIndex:0] : nil;
        NSString *timeExpression = tokens.count > 1 ? [tokens objectAtIndex:1] : nil;
        return [[UDGuiResetTimeCommand alloc] initWithWindowName:windowName timeExpression:timeExpression];
    }

    if ([lower isEqualToString:@"transition"] && tokens.count >= 4) {
        NSString *accel = tokens.count > 4 ? [tokens objectAtIndex:4] : nil;
        NSString *decel = tokens.count > 5 ? [tokens objectAtIndex:5] : nil;
        return [[UDGuiTransitionCommand alloc] initWithVariable:[tokens objectAtIndex:0]
                                                      fromValue:[tokens objectAtIndex:1]
                                                        toValue:[tokens objectAtIndex:2]
                                                 timeExpression:[tokens objectAtIndex:3]
                                                accelExpression:accel
                                                decelExpression:decel];
    }

    if (([lower isEqualToString:@"showcursor"] ||
         [lower isEqualToString:@"localsound"] ||
         [lower isEqualToString:@"runscript"]) && tokens.count > 0) {
        return [[UDGuiSingleArgumentCommand alloc] initWithKeyword:keyword value:[tokens objectAtIndex:0]];
    }

    return [[UDGuiScriptCommand alloc] initWithKeyword:keyword arguments:arguments ?: @""];
}

- (NSString *)serializedScriptBlockForEventHandler:(UDGuiEventHandler *)eventHandler indent:(NSString *)indent {
    NSMutableString *block = [NSMutableString stringWithFormat:@"%@%@", [eventHandler eventKeyword], [eventHandler eventQualifier].length > 0 ? [NSString stringWithFormat:@" %@", [eventHandler eventQualifier]] : @""];
    [block appendString:@" {\n"];
    NSString *lineIndent = [indent stringByAppendingString:@"    "];

    if (eventHandler.commands.count == 1) {
        UDGuiScriptCommand *command = [eventHandler.commands objectAtIndex:0];
        if ([command.keyword isEqualToString:UDGuiRawScriptBodyCommandKeyword]) {
            NSString *rawBody = command.arguments ?: @"";
            if (rawBody.length > 0) {
                NSArray<NSString *> *rawLines = [rawBody componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                for (NSString *line in rawLines) {
                    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (trimmed.length == 0) {
                        continue;
                    }
                    [block appendFormat:@"%@%@\n", lineIndent, trimmed];
                }
            }
            [block appendFormat:@"%@}", indent];
            return block;
        }
    }

    for (UDGuiScriptCommand *command in eventHandler.commands) {
        if ([command isKindOfClass:[UDGuiIfCommand class]]) {
            [block appendFormat:@"%@%@\n", lineIndent, [self serializeScriptCommand:command]];
        } else {
            [block appendFormat:@"%@%@ ;\n", lineIndent, [self serializeScriptCommand:command]];
        }
    }
    [block appendFormat:@"%@}", indent];
    return block;
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
        if ([self isEventHandlerIdentifier:property.key]) {
            continue;
        }
        [text appendFormat:@"%@    %@ %@\n", indent, property.key, [self serializePropertyValue:property.value ?: @""]];
    }

    for (UDGuiEventHandler *eventHandler in window.eventHandlers) {
        [text appendFormat:@"%@    %@\n", indent, [self serializedScriptBlockForEventHandler:eventHandler indent:[indent stringByAppendingString:@"    "]]];
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

- (NSString *)serializeExpression:(UDGuiExpression *)expression {
    if (!expression) {
        return @"";
    }
    UDGuiExpressionSerializer *serializer = [[UDGuiExpressionSerializer alloc] init];
    return [expression acceptVisitor:serializer];
}

- (NSString *)serializeScriptCommand:(UDGuiScriptCommand *)command {
    if (!command) {
        return @"";
    }
    if ([command isKindOfClass:[UDGuiIfCommand class]]) {
        UDGuiIfCommand *ifCmd = (UDGuiIfCommand *)command;
        NSMutableString *result = [NSMutableString string];
        for (NSUInteger idx = 0; idx < ifCmd.branches.count; idx++) {
            UDGuiIfBranch *branch = [ifCmd.branches objectAtIndex:idx];
            if (idx > 0) {
                [result appendString:@" "];
            }
            if (branch.condition) {
                NSString *condStr = [self serializeExpression:branch.condition];
                if (idx == 0) {
                    [result appendFormat:@"if ( %@ ) {", condStr];
                } else {
                    [result appendFormat:@"else if ( %@ ) {", condStr];
                }
            } else {
                [result appendString:@"else {"];
            }
            
            for (UDGuiScriptCommand *cmd in branch.commands) {
                [result appendFormat:@" %@ ;", [self serializeScriptCommand:cmd]];
            }
            
            [result appendString:@" }"];
        }
        return result;
    } else {
        NSString *trimmedArguments = [command.arguments stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return trimmedArguments.length > 0 ? [NSString stringWithFormat:@"%@ %@", command.keyword, trimmedArguments] : command.keyword;
    }
}

@end
