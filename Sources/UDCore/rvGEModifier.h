/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEModifier.h — the GUI editor's edits (tools/guied/GEModifier.h,
 * GEModifierGroup, GEMoveModifier, GESizeModifier; GEModifierStack), ported:
 * each an edit of a window that applies and undoes itself, and merges with
 * the same edit after it (a drag's moves are one); and the stack of them.
 *
 * The stack is the engine's (its own undo and redo, its merging); given an
 * NSUndoManager, it also registers each edit there (target-action), so a
 * document's Undo and Redo, its dirty state and its menu names go with it.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"

@class idWindow, rvGEWindowWrapper, idDict;

NS_ASSUME_NONNULL_BEGIN

@interface rvGEModifier : NSObject
- (instancetype)initWithName:(NSString *)name window:(nullable idWindow *)window;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, strong, readonly, nullable) idWindow *window;
@property (nonatomic, strong, readonly, nullable) rvGEWindowWrapper *wrapper;
- (BOOL)apply;
- (BOOL)undo;
- (BOOL)canMerge:(rvGEModifier *)merge;
- (BOOL)isValid;
- (BOOL)merge:(rvGEModifier *)merge;
@end

/// rvGEModifierGroup: edits of the same kind, of several windows, as one.
@interface rvGEModifierGroup : rvGEModifier
- (instancetype)init;
- (BOOL)append:(rvGEModifier *)mod;
@property (nonatomic, copy, readonly) NSArray<rvGEModifier *> *modifiers;
@end

/// rvGEMoveModifier: a window moved by ( @a x, @a y ).
@interface rvGEMoveModifier : rvGEModifier
- (instancetype)initWithName:(NSString *)name window:(idWindow *)window x:(float)x y:(float)y;
@end

/// rvGESizeModifier: a window's sides moved by @a l, @a t, @a r, @a b.
@interface rvGESizeModifier : rvGEModifier
- (instancetype)initWithName:(NSString *)name window:(idWindow *)window l:(float)l t:(float)t r:(float)r b:(float)b;
@end

/// rvGEHideModifier: a window hidden in the editor, or shown (and, shown,
/// the nearest hidden window it is in too). The editor's alone: the file's
/// "visible" is as it was.
@interface rvGEHideModifier : rvGEModifier
- (instancetype)initWithName:(NSString *)name window:(idWindow *)window hide:(BOOL)hide;
@end

/// rvGEStateModifier: a window's state keys as @a dict has them.
@interface rvGEStateModifier : rvGEModifier
- (instancetype)initWithName:(NSString *)name window:(idWindow *)window dict:(idDict *)dict;
@end

/// rvGEModifierStack
@interface rvGEModifierStack : NSObject

/// Where the edits are registered too, if anywhere (a document's).
@property (nonatomic, weak, nullable) NSUndoManager *undoManager;

- (void)reset;
/// Append: @a modifier applied, merged into the last if it can be (and the
/// last was not blocked from merging), else pushed, the redos dropped. NO
/// for an invalid one.
- (BOOL)append:(rvGEModifier *)modifier;
- (BOOL)undo;
- (BOOL)redo;
- (BOOL)canUndo;
- (BOOL)canRedo;
/// The next edit appended starts a new one (a new drag).
- (void)blockNextMerge;
- (nullable rvGEModifier *)undoModifier;
- (nullable rvGEModifier *)redoModifier;

/// Told after an edit, an undo or a redo (target-action; sender the stack).
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;

@end

NS_ASSUME_NONNULL_END
