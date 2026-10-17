/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclTable.h — tables (idDeclTable).
 */

#import "UDDeclElement.h"

@class idDeclManager;

NS_ASSUME_NONNULL_BEGIN

/// One of a table's values.
@interface UDTableValue : UDDeclElement
@property (nonatomic) float number;
+ (instancetype)valueWithNumber:(float)number;
@end

@interface UDDeclTable : UDDeclBase

@property (nonatomic) BOOL clamp;
@property (nonatomic) BOOL snap;
/// The values, in order. TRANSIENT: read from the decl text on fetch and
/// written back on save; a new array marks the decl updated.
@property (nonatomic, copy, nullable) NSArray<UDTableValue *> *values;


/// idDeclTable::TableLookup( @a index ) of the table decl @a name in
/// @a declManager (its values as idDeclTable::Parse leaves them, the first
/// copied to the end); 1 for none, as a table of no domain is.
+ (float)ud_lookup:(float)index inTableNamed:(NSString *)name declManager:(nullable idDeclManager *)declManager;
@end

NS_ASSUME_NONNULL_END
