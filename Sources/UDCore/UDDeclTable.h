/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclTable.h — tables (idDeclTable).
 */

#import "UDDeclElement.h"

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

@end

NS_ASSUME_NONNULL_END
