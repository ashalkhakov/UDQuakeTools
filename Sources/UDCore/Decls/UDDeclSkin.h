/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclSkin.h — skins (idDeclSkin).
 */

#import "UDDeclElement.h"

NS_ASSUME_NONNULL_BEGIN

/// One of a skin's mappings: from a material ("*" for all) to another.
@interface UDSkinMapping : UDDeclElement
@property (nonatomic, copy) NSString *from;
@property (nonatomic, copy) NSString *to;
+ (instancetype)mappingFrom:(NSString *)from to:(NSString *)to;
@end

/// One of the models a skin goes with.
@interface UDSkinModel : UDDeclElement
@property (nonatomic, copy) NSString *path;
+ (instancetype)modelWithPath:(NSString *)path;
@end

@interface UDDeclSkin : UDDeclBase

/// The mappings and the associated models, in order. TRANSIENT, as a
/// table's values are.
@property (nonatomic, copy, nullable) NSArray<UDSkinMapping *> *mappings;
@property (nonatomic, copy, nullable) NSArray<UDSkinModel *> *associatedModels;

@end

NS_ASSUME_NONNULL_END
