/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclElement.h — the elements of a decl's transient lists.
 */

#import "UDDeclBase.h"

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// A table's values and a skin's mappings and models: like particle stages,
// plain KVO-compliant objects in transient attributes of their decl, read
// from its text on fetch and written back on save. An element belongs to its
// decl: setting a property of one asks the decl to put an edited copy in its
// place, in a new array, so a bound cell's edit is the decl's (undoable, the
// decl updated) and undo brings the element back as it was.
// ---------------------------------------------------------------------------

@interface UDDeclElement : NSObject <NSCopying>
/// The decl and its attribute holding this element; nil until it is in one.
@property (nonatomic, weak, nullable) UDDeclBase *ud_owner;
@property (nonatomic, copy, nullable) NSString *ud_ownerKey;
@end

/// An element of many values (a particle stage, an FX action): its declared
/// properties are its values, copied with it; one set through KVC (a
/// binding's edit) puts an edited copy in its place. A number typed in is
/// validated: its scalar properties' and +ud_numberKeys' (NSNumber, nothing
/// for none).
@interface UDDeclPropertyElement : UDDeclElement
+ (NSArray<NSString *> *)ud_valueKeys;
+ (NSSet<NSString *> *)ud_numberKeys;
@end

NS_ASSUME_NONNULL_END
