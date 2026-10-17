/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGETransformer.h — the GUI editor's transformer (tools/guied/
 * GETransformer.cpp), ported without its window: the selection's rect,
 * relative to the bottom-most selected window's parent, and an edit of
 * one of its four numbers made a move or a size of the selection. Quarry
 * shows it as the inspector's Layout.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"

@class rvGEWorkspace;

NS_ASSUME_NONNULL_BEGIN

/// The transformer's fields (IDC_GUIED_ITEMRECTX, Y, W, H).
typedef NS_ENUM(NSInteger, rvGETransformerField) {
    rvGETransformerX,
    rvGETransformerY,
    rvGETransformerW,
    rvGETransformerH,
};

@interface rvGETransformer : NSObject

- (instancetype)initWithWorkspace:(nullable rvGEWorkspace *)workspace;

@property (nonatomic, weak, nullable) rvGEWorkspace *workspace;

/// Update: whether there is a selection to transform (the fields enabled),
/// and its rect, as the fields show it (whole numbers).
- (BOOL)update:(idRectangle *)rect;

/// EN_KILLFOCUS: @a field set to @a value, the selection moved ("Transform
/// Move") or sized ("Transform Size") by the difference, if any.
- (void)setField:(rvGETransformerField)field value:(int)value;

@end

NS_ASSUME_NONNULL_END
