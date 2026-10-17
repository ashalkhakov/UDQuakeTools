/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEScript.m
 */

#import "rvGEScript.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

/// idGuiScript's command list: its name, the least and most parameters it
/// takes, what they are, and what it does.
typedef struct {
    NSString *__unsafe_unretained name;
    int minParms;
    int maxParms;
} rvGECommand;

static const rvGECommand rvGECommands[] = {
    { @"set", 2, 999 },
    { @"setFocus", 1, 1 },
    { @"endGame", 0, 0 },
    { @"resetTime", 0, 2 },
    { @"showCursor", 1, 1 },
    { @"resetCinematics", 0, 2 },
    { @"transition", 4, 6 },
    { @"localSound", 1, 1 },
    { @"runScript", 1, 1 },
    { @"evalRegs", 0, 0 },
};
static const int rvGECommandCount = sizeof(rvGECommands) / sizeof(rvGECommands[0]);

static const rvGECommand *rvGEFindCommand(NSString *name) {
    for (int i = 0; i < rvGECommandCount; i++) {
        if ([rvGECommands[i].name caseInsensitiveCompare:name] == NSOrderedSame) {
            return &rvGECommands[i];
        }
    }
    return NULL;
}

/// A string as a script writes it: the lexer's escapes put back
/// (idLexer::ReadEscapeCharacter's \\ \n \r \t \").
static NSString *rvGEEscaped(NSString *text) {
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        switch (c) {
            case '\\': [out appendString:@"\\\\"]; break;
            case '\n': [out appendString:@"\\n"]; break;
            case '\r': [out appendString:@"\\r"]; break;
            case '\t': [out appendString:@"\\t"]; break;
            case '"': [out appendString:@"\\\""]; break;
            default: [out appendFormat:@"%C", c]; break;
        }
    }
    return out;
}

/// A token as the script had it: a string quoted again, its escapes put
/// back.
static NSString *rvGETokenText(const idToken *token) {
    NSString *text = UDTokenLatin1String(token);
    if (token->type == TT_STRING) {
        return [NSString stringWithFormat:@"\"%@\"", rvGEEscaped(text)];
    }
    return text;
}

static BOOL rvGETokenIs(const idToken *token, const char *text) {
    return UDTokenIcmp(token, text);
}

@implementation rvGEScriptStatement

+ (instancetype)statementWithCommand:(NSString *)command {
    rvGEScriptStatement *statement = [[rvGEScriptStatement alloc] init];
    statement.command = command;
    if (statement.isIf) {
        statement.condition = @"1";
    } else {
        NSInteger count = [rvGEScript minimumParametersOf:command];
        for (NSInteger i = 0; i < count; i++) {
            [statement.arguments addObject:@""];
        }
    }
    return statement;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _command = @"";
        _arguments = [NSMutableArray array];
        _condition = @"";
        _statements = [NSMutableArray array];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    rvGEScriptStatement *copy = [[rvGEScriptStatement alloc] init];
    copy.command = self.command;
    copy.arguments = [self.arguments mutableCopy];
    copy.condition = self.condition;
    copy.statements = [[NSMutableArray alloc] initWithArray:self.statements copyItems:YES];
    copy.elseStatements = self.elseStatements ? [[NSMutableArray alloc] initWithArray:self.elseStatements copyItems:YES] : nil;
    return copy;
}

- (BOOL)isIf {
    return [self.command caseInsensitiveCompare:@"if"] == NSOrderedSame;
}

- (NSString *)summary {
    if (self.isIf) {
        return [NSString stringWithFormat:@"if %@", self.condition];
    }
    NSMutableString *line = [NSMutableString stringWithString:self.command];
    for (NSString *argument in self.arguments) {
        [line appendFormat:@" \"%@\"", argument];
    }
    return line;
}

@end

@implementation rvGEScript

#pragma mark - Reading (idWindow::ParseScript, idGuiScript::Parse)

/// An if's condition: what idWindow::ParseExpression reads, up to the
/// block's brace (the parentheses kept).
+ (nullable NSString *)_conditionFrom:(idLexer *)src {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    idToken token;
    idToken_Init(&token);
    int depth = 0;
    while ([src readToken:&token error:NULL]) {
        if (depth == 0 && rvGETokenIs(&token, "{")) {
            [src unreadToken:&token error:NULL];
            return [parts componentsJoinedByString:@" "];
        }
        if (rvGETokenIs(&token, "(")) depth++;
        if (rvGETokenIs(&token, ")")) depth--;
        [parts addObject:rvGETokenText(&token)];
    }
    return nil;
}

/// ParseScript: a braced list of statements into @a list (an else's may be
/// a lone if, an "else if").
+ (BOOL)_parse:(idLexer *)src into:(NSMutableArray<rvGEScriptStatement *> *)list elseBlock:(BOOL)elseBlock
       message:(NSString **)message {
    idToken token;
    idToken_Init(&token);
    BOOL ifElseBlock = NO;

    if (elseBlock) {
        if (![src readToken:&token error:NULL]) {
            *message = @"Unexpected end of script";
            return NO;
        }
        ifElseBlock = rvGETokenIs(&token, "if");
        [src unreadToken:&token error:NULL];
        if (!ifElseBlock && ![src expectTokenString:@"{" error:NULL]) {
            *message = @"expected { after else";
            return NO;
        }
    } else if (![src expectTokenString:@"{" error:NULL]) {
        *message = @"expected {";
        return NO;
    }

    while (1) {
        if (![src readToken:&token error:NULL]) {
            *message = @"Unexpected end of script";
            return NO;
        }
        if (rvGETokenIs(&token, "}")) {
            return YES;
        }
        if (rvGETokenIs(&token, "if")) {
            rvGEScriptStatement *statement = [[rvGEScriptStatement alloc] init];
            statement.command = @"if";
            NSString *condition = [self _conditionFrom:src];
            if (condition == nil) {
                *message = @"if: expected a condition and {";
                return NO;
            }
            statement.condition = condition;
            if (![self _parse:src into:statement.statements elseBlock:NO message:message]) {
                return NO;
            }
            if ([src readToken:&token error:NULL]) {
                if (rvGETokenIs(&token, "else")) {
                    statement.elseStatements = [NSMutableArray array];
                    if (![self _parse:src into:statement.elseStatements elseBlock:YES message:message]) {
                        return NO;
                    }
                } else {
                    [src unreadToken:&token error:NULL];
                }
            }
            [list addObject:statement];
            // an "else if": the first if reads on
            if (ifElseBlock) {
                return YES;
            }
            continue;
        }
        // empty { } is not allowed
        if (rvGETokenIs(&token, "{")) {
            *message = @"Unexpected {";
            return NO;
        }

        // idGuiScript::Parse: the command, its parameters to ;
        const rvGECommand *command = rvGEFindCommand(UDTokenLatin1String(&token));
        if (command == NULL) {
            *message = [NSString stringWithFormat:@"Unknown script call %@", UDTokenLatin1String(&token)];
            return NO;
        }
        rvGEScriptStatement *statement = [[rvGEScriptStatement alloc] init];
        statement.command = command->name;
        while (1) {
            if (![src readToken:&token error:NULL]) {
                *message = @"Unexpected end of script";
                return NO;
            }
            if (rvGETokenIs(&token, ";")) {
                break;
            }
            if (rvGETokenIs(&token, "}")) {
                [src unreadToken:&token error:NULL];
                break;
            }
            // as the script writes it: a string's escapes kept
            [statement.arguments addObject:token.type == TT_STRING ? rvGEEscaped(UDTokenLatin1String(&token)) : UDTokenLatin1String(&token)];
        }
        [list addObject:statement];
    }
}

+ (NSMutableArray<rvGEScriptStatement *> *)statementsFromText:(NSString *)text message:(NSString **)message {
    NSString *why = nil;
    NSData *bytes __attribute__((objc_precise_lifetime)) = [text ud_latin1Buffer];
    idLexer *src = [[idLexer alloc] initWithBuffer:bytes.bytes length:(int)bytes.length - 1 name:@""
                                             flags:LEXFL_ALLOWMULTICHARLITERALS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWBACKSLASHSTRINGCONCAT | LEXFL_NOERRORS
                                        fileSystem:nil error:NULL];
    NSMutableArray<rvGEScriptStatement *> *statements = [NSMutableArray array];
    if (![self _parse:src into:statements elseBlock:NO message:&why]) {
        if (message) *message = why;
        return nil;
    }
    return statements;
}

#pragma mark - Writing

static NSString *rvGEQuoted(NSString *text) {
    return [NSString stringWithFormat:@"\"%@\"", text];
}

+ (void)_write:(NSArray<rvGEScriptStatement *> *)statements depth:(int)depth into:(NSMutableString *)out {
    NSString *tabs = [@"" stringByPaddingToLength:(NSUInteger)depth withString:@"\t" startingAtIndex:0];
    for (rvGEScriptStatement *statement in statements) {
        if (statement.isIf) {
            [out appendFormat:@"%@if %@ {\n", tabs, statement.condition];
            [self _write:statement.statements depth:depth + 1 into:out];
            if (statement.elseStatements != nil) {
                [out appendFormat:@"%@} else {\n", tabs];
                [self _write:statement.elseStatements depth:depth + 1 into:out];
            }
            [out appendFormat:@"%@}\n", tabs];
            continue;
        }
        [out appendFormat:@"%@%@", tabs, statement.command];
        for (NSString *argument in statement.arguments) {
            [out appendFormat:@" %@", rvGEQuoted(argument)];
        }
        [out appendString:@" ;\n"];
    }
}

+ (NSString *)textFromStatements:(NSArray<rvGEScriptStatement *> *)statements {
    NSMutableString *out = [NSMutableString stringWithString:@"{\n"];
    [self _write:statements depth:1 into:out];
    [out appendString:@"}"];
    return out;
}

#pragma mark - The commands

+ (NSArray<NSString *> *)commands {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (int i = 0; i < rvGECommandCount; i++) {
        [names addObject:rvGECommands[i].name];
    }
    [names addObject:@"if"];
    return names;
}

+ (NSInteger)minimumParametersOf:(NSString *)command {
    const rvGECommand *c = rvGEFindCommand(command);
    return c ? c->minParms : 0;
}

+ (NSArray<NSString *> *)parameterNamesOf:(NSString *)command {
    static NSDictionary<NSString *, NSArray<NSString *> *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"set": @[@"Variable", @"Value"],
            @"setfocus": @[@"Window"],
            @"resettime": @[@"Window", @"Time"],
            @"showcursor": @[@"Shown"],
            @"transition": @[@"Variable", @"From", @"To", @"Time", @"Accel", @"Decel"],
            @"localsound": @[@"Sound"],
            @"runscript": @[@"Function"],
        };
    });
    return names[command.lowercaseString] ?: @[];
}

+ (NSString *)helpOf:(NSString *)command {
    static NSDictionary<NSString *, NSString *> *help;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        help = @{
            @"set": @"Sets a variable: one of this window's, another's (Window::name), or the GUI's state (gui::name). Set \"cmd\" to send the game a command.",
            @"setfocus": @"Gives a window the keyboard's focus.",
            @"endgame": @"Ends the game (the main menu's Quit).",
            @"resettime": @"Starts a window's time again from a time, in milliseconds: its onTime events run again from there. With one parameter, this window's.",
            @"showcursor": @"Shows the cursor (1) or hides it (0).",
            @"resetcinematics": @"Starts this window's cinematics (videos) again from their start.",
            @"transition": @"Moves a rect, a color or a number from one value to another over a time, easing in and out.",
            @"localsound": @"Plays a sound shader for the player alone.",
            @"runscript": @"Runs a game script function, after the commands set before it.",
            @"evalregs": @"Evaluates the window's expressions again now.",
            @"if": @"Runs its statements while the condition is not 0, else the else block's.",
        };
    });
    return help[command.lowercaseString] ?: @"";
}

+ (NSString *)helpOf:(NSString *)command parameter:(NSInteger)index {
    static NSDictionary<NSString *, NSArray<NSString *> *> *help;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        help = @{
            @"set": @[@"The variable: name (this window's), Window::name, gui::name, or cmd.",
                      @"The value it is set to; for cmd, the command (more values are its quoted arguments)."],
            @"setfocus": @[@"The window that takes the focus."],
            @"resettime": @[@"The window whose time starts again (or, alone, the time, for this window).",
                            @"The time it starts from, in milliseconds."],
            @"showcursor": @[@"1 shows the cursor, 0 hides it."],
            @"transition": @[@"What moves: a window's rect, a color (forecolor, backcolor, matcolor) or a number, as Window::name.",
                             @"Where it starts: four numbers, \"x y w h\" or \"r g b a\".",
                             @"Where it ends.",
                             @"How long it takes, in milliseconds.",
                             @"The fraction of the time it speeds up over (0 to 1).",
                             @"The fraction of the time it slows down over (0 to 1)."],
            @"localsound": @[@"The sound shader played."],
            @"runscript": @[@"The game script function run."],
        };
    });
    NSArray<NSString *> *each = help[command.lowercaseString];
    if (index >= 0 && index < (NSInteger)each.count) return each[(NSUInteger)index];
    if ([command caseInsensitiveCompare:@"set"] == NSOrderedSame) return @"A further argument of the command (for cmd).";
    return @"";
}

#pragma mark - The events

+ (NSArray<NSString *> *)events {
    // idWindow's script names, onTime and onNamedEvent (ParseScriptEntry's,
    // Parse's), and a scriptDef
    return @[@"onAction", @"onActionRelease", @"onMouseEnter", @"onMouseExit", @"onActivate", @"onDeactivate",
             @"onESC", @"onEnter", @"onEnterRelease", @"onTrigger", @"onEvent", @"onTime", @"onNamedEvent"];
}

+ (NSString *)helpOfEvent:(NSString *)event {
    static NSDictionary<NSString *, NSString *> *help;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        help = @{
            @"onaction": @"When the window is clicked.",
            @"onactionrelease": @"When the click on the window is let go.",
            @"onmouseenter": @"When the cursor moves onto the window.",
            @"onmouseexit": @"When the cursor moves off the window.",
            @"onactivate": @"When the GUI is shown (activated).",
            @"ondeactivate": @"When the GUI is put away (deactivated).",
            @"onesc": @"When Escape is pressed.",
            @"onenter": @"When Enter is pressed (in an edit window).",
            @"onenterrelease": @"When Enter is let go.",
            @"ontrigger": @"When the GUI's entity is triggered.",
            @"onevent": @"Every frame the GUI runs.",
            @"ontime": @"At a time, in milliseconds, after the window's time starts (resetTime starts it again).",
            @"onnamedevent": @"When the game or a script sends the GUI the named event.",
        };
    });
    return help[event.lowercaseString] ?: @"";
}

+ (NSString *)keyOfEvent:(NSString *)event parameter:(NSString *)parameter {
    if (parameter.length > 0 && ([event caseInsensitiveCompare:@"onTime"] == NSOrderedSame ||
                                 [event caseInsensitiveCompare:@"onNamedEvent"] == NSOrderedSame)) {
        return [NSString stringWithFormat:@"%@ %@", event, parameter];
    }
    return event;
}

+ (NSString *)eventOfKey:(NSString *)key {
    NSRange space = [key rangeOfString:@" "];
    return space.location == NSNotFound ? key : [key substringToIndex:space.location];
}

+ (NSString *)parameterOfKey:(NSString *)key {
    NSRange space = [key rangeOfString:@" "];
    return space.location == NSNotFound ? nil : [key substringFromIndex:NSMaxRange(space)];
}

@end
