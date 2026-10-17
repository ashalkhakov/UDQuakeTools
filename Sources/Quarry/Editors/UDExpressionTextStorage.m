/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDExpressionTextStorage.m
 */

#import "UDExpressionTextStorage.h"

static NSColor *UDInk(NSString *kind) {
    if ([kind isEqualToString:@"number"]) return [NSColor colorWithCalibratedRed:0.30 green:0.55 blue:0.85 alpha:1];
    if ([kind isEqualToString:@"string"]) return [NSColor colorWithCalibratedRed:0.75 green:0.40 blue:0.20 alpha:1];
    if ([kind isEqualToString:@"name"]) return [NSColor colorWithCalibratedRed:0.20 green:0.55 blue:0.45 alpha:1];
    if ([kind isEqualToString:@"table"]) return [NSColor colorWithCalibratedRed:0.45 green:0.35 blue:0.75 alpha:1];
    if ([kind isEqualToString:@"operator"]) return [NSColor colorWithCalibratedWhite:0.55 alpha:1];
    return nil;
}

@implementation UDExpressionTextStorage {
    // NSTextStorage is a semi-abstract class: a subclass supplies the storage
    // and the four primitives below, and inherits everything else.
    NSMutableAttributedString *_backing;
    NSDictionary<NSString *, id> *_baseAttributes;
    BOOL _colouring;
}

+ (instancetype)installedInTextView:(NSTextView *)view {
    NSLayoutManager *layoutManager = view.layoutManager;
    if (layoutManager == nil) return nil;
    UDExpressionTextStorage *storage = [[self alloc] init];
    // Paper, not ink: an expression is read on white whatever the appearance
    // (GNUstep in a dark theme draws the view black, and the colours vanish).
    view.drawsBackground = YES;
    view.backgroundColor = [NSColor whiteColor];
    view.insertionPointColor = [NSColor blackColor];
    [storage replaceCharactersInRange:NSMakeRange(0, 0) withString:view.textStorage.string ?: @""];
    [layoutManager replaceTextStorage:storage];
    return view.textStorage == storage ? storage : nil;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _backing = [[NSMutableAttributedString alloc] init];
        _knownNames = [NSSet set];
        _tableNames = [NSSet set];
        // black, not controlTextColor: the text is on white
        _baseAttributes = @{
            NSFontAttributeName: [NSFont userFixedPitchFontOfSize:12] ?: [NSFont systemFontOfSize:12],
            NSForegroundColorAttributeName: [NSColor blackColor],
        };
    }
    return self;
}

#pragma mark - NSTextStorage's primitives

- (NSString *)string {
    return _backing.string;
}

- (NSDictionary<NSString *, id> *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range {
    return [_backing attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string {
    [_backing replaceCharactersInRange:range withString:string];
    [self edited:NSTextStorageEditedCharacters range:range changeInLength:(NSInteger)string.length - (NSInteger)range.length];
}

- (void)setAttributes:(NSDictionary<NSString *, id> *)attributes range:(NSRange)range {
    [_backing setAttributes:attributes range:range];
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

#pragma mark - Colouring

static BOOL UDIsNameStart(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static BOOL UDIsNamePart(unichar c) {
    return UDIsNameStart(c) || (c >= '0' && c <= '9') || c == ':';
}

+ (NSArray<NSArray *> *)tokensOf:(NSString *)text known:(NSSet<NSString *> *)known tables:(NSSet<NSString *> *)tables {
    NSMutableSet<NSString *> *knownLower = [NSMutableSet set];
    for (NSString *name in known) [knownLower addObject:name.lowercaseString];
    NSMutableSet<NSString *> *tablesLower = [NSMutableSet set];
    for (NSString *name in tables) [tablesLower addObject:name.lowercaseString];
    NSMutableArray<NSArray *> *tokens = [NSMutableArray array];
    NSUInteger length = text.length;
    NSUInteger i = 0;
    while (i < length) {
        unichar c = [text characterAtIndex:i];
        NSUInteger start = i;
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            i++;
            continue;
        }
        if ((c >= '0' && c <= '9') || (c == '.' && i + 1 < length && [text characterAtIndex:i + 1] >= '0' && [text characterAtIndex:i + 1] <= '9')) {
            while (i < length && (([text characterAtIndex:i] >= '0' && [text characterAtIndex:i] <= '9') || [text characterAtIndex:i] == '.')) i++;
            [tokens addObject:@[@(start), @(i - start), @"number"]];
            continue;
        }
        if (c == '"') {
            i++;
            while (i < length && [text characterAtIndex:i] != '"') {
                if ([text characterAtIndex:i] == '\\') i++;
                i++;
            }
            if (i < length) i++;
            [tokens addObject:@[@(start), @(MIN(i, length) - start), @"string"]];
            continue;
        }
        if (UDIsNameStart(c)) {
            while (i < length && UDIsNamePart([text characterAtIndex:i])) i++;
            NSString *name = [text substringWithRange:NSMakeRange(start, i - start)].lowercaseString;
            NSUInteger next = i;
            while (next < length && [text characterAtIndex:next] == ' ') next++;
            BOOL lookup = next < length && [text characterAtIndex:next] == '[';
            if (lookup && [tablesLower containsObject:name]) {
                [tokens addObject:@[@(start), @(i - start), @"table"]];
            } else if ([knownLower containsObject:name]) {
                [tokens addObject:@[@(start), @(i - start), @"name"]];
            }
            continue;
        }
        if ([@"+-*/%=!<>&|()[],;" rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound) {
            [tokens addObject:@[@(start), @1, @"operator"]];
        }
        i++;
    }
    return tokens;
}

// The whole text, every time (an expression is short, and a quote or a
// bracket changes what follows it). The mask is read before -[super
// processEditing], which clears it; colouring is itself an edit, which must
// not colour again.
- (void)processEditing {
    NSUInteger mask = self.editedMask;
    [super processEditing];
    if (_colouring || (mask & NSTextStorageEditedCharacters) == 0) return;
    _colouring = YES;
    NSUInteger length = _backing.length;
    if (length > 0) {
        [self setAttributes:_baseAttributes range:NSMakeRange(0, length)];
        for (NSArray *token in [UDExpressionTextStorage tokensOf:_backing.string known:self.knownNames tables:self.tableNames]) {
            NSRange range = NSMakeRange([token[0] unsignedIntegerValue], [token[1] unsignedIntegerValue]);
            NSColor *ink = UDInk(token[2]);
            // a zero-length run has nothing to colour, and GNUstep logs it
            if (ink != nil && range.length > 0 && NSMaxRange(range) <= length) {
                [self addAttribute:NSForegroundColorAttributeName value:ink range:range];
            }
        }
    }
    _colouring = NO;
}

@end
