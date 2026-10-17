/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEScript.h — a window's scripts as statements, not text (not the
 * engine's: its editor edited them as text, GEItemScriptsDlg). A script
 * (an event's braced section, as the window wrapper keeps it) is read as
 * idWindow::ParseScript and idGuiScript::Parse read it: commands of
 * idGuiScript's command list with their parameters, and if, its condition
 * and its blocks; and written back as the engine's GUIs write them.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One statement: a command and its parameters, or an if.
@interface rvGEScriptStatement : NSObject <NSCopying>

/// A command made new: its parameters as many as it needs, empty.
+ (instancetype)statementWithCommand:(NSString *)command;

/// The command (set, transition, …) as the command list names it, or "if".
@property (nonatomic, copy) NSString *command;
/// Its parameters, as the script writes them inside their quotes (a
/// string's escapes, \n and \", kept).
@property (nonatomic, strong) NSMutableArray<NSString *> *arguments;
/// An if's condition (an expression's text), its statements, and its else
/// block's (nil when it has none).
@property (nonatomic, copy) NSString *condition;
@property (nonatomic, strong) NSMutableArray<rvGEScriptStatement *> *statements;
@property (nonatomic, strong, nullable) NSMutableArray<rvGEScriptStatement *> *elseStatements;
@property (nonatomic, readonly) BOOL isIf;

/// The statement on one line, as the script would have it (an if: its
/// condition only).
- (NSString *)summary;

@end

/// The language: its commands, their parameters, its events; reading and
/// writing a script.
@interface rvGEScript : NSObject

/// @a text (a braced section) as statements; nil, and why in @a message,
/// when it does not read.
+ (nullable NSMutableArray<rvGEScriptStatement *> *)statementsFromText:(NSString *)text
                                                               message:(NSString *_Nullable *_Nullable)message;
/// The statements as a braced section, a tab each level in.
+ (NSString *)textFromStatements:(NSArray<rvGEScriptStatement *> *)statements;

/// idGuiScript's command list's names, then "if".
+ (NSArray<NSString *> *)commands;
/// What each of a command's parameters is (the ones it may go without
/// last), and how many it needs at least.
+ (NSArray<NSString *> *)parameterNamesOf:(NSString *)command;
+ (NSInteger)minimumParametersOf:(NSString *)command;
/// What the command does, and each parameter (by its index).
+ (NSString *)helpOf:(NSString *)command;
+ (NSString *)helpOf:(NSString *)command parameter:(NSInteger)index;

/// The events a window has scripts for (idWindow's script names, onTime,
/// onNamedEvent), and what each is.
+ (NSArray<NSString *> *)events;
+ (NSString *)helpOfEvent:(NSString *)event;
/// A script's key (as the wrapper keeps it: "onTime 500") made of an event
/// and its parameter, and taken apart.
+ (NSString *)keyOfEvent:(NSString *)event parameter:(nullable NSString *)parameter;
+ (NSString *)eventOfKey:(NSString *)key;
+ (nullable NSString *)parameterOfKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
