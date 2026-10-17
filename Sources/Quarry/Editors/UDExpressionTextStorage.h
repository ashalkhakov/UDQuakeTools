/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDExpressionTextStorage.h — an expression's text, coloured as it is
 * typed: RDLKit's RDLExpressionTextStorage (an NSTextStorage subclass that
 * colours the whole text after each edit), its tokens an idTech
 * expression's — numbers, strings, the names it knows (parms, tables,
 * variables), a table's lookup, operators.
 */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDExpressionTextStorage : NSTextStorage

/// A storage put in @a view's place (its text kept), on white whatever the
/// appearance; nil if the view would not take it.
+ (nullable instancetype)installedInTextView:(NSTextView *)view;

/// The names coloured as known (case ignored), and the tables (coloured as
/// a lookup before a "[").
@property (nonatomic, copy) NSSet<NSString *> *knownNames;
@property (nonatomic, copy) NSSet<NSString *> *tableNames;

/// The colour each run of @a text would get (for the tests): runs of
/// (location, length, kind) with kind "number", "string", "name", "table",
/// "operator".
+ (NSArray<NSArray *> *)tokensOf:(NSString *)text known:(NSSet<NSString *> *)known tables:(NSSet<NSString *> *)tables;

@end

NS_ASSUME_NONNULL_END
