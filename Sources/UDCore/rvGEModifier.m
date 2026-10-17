/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEModifier.m — tools/guied/GEModifier.cpp, GEModifierGroup.cpp,
 * GEMoveModifier.cpp, GESizeModifier.cpp, GEModifierStack.cpp, ported.
 */

#import "rvGEModifier.h"
#import "rvGEWindowWrapper.h"
#import "idWindow.h"
#import "idStr.h"
#import "idDict.h"

@implementation rvGEModifier

- (instancetype)initWithName:(NSString *)name window:(idWindow *)window {
    self = [super init];
    if (self) {
        _window = window;
        _name = [name copy];
        if ( _window ) {
            _wrapper = [rvGEWindowWrapper wrapperOf:window];
        }
    }
    return self;
}

- (BOOL)apply {
    return NO;
}

- (BOOL)undo {
    return NO;
}

- (BOOL)canMerge:(rvGEModifier *)merge {
    return NO;
}

- (BOOL)isValid {
    return YES;
}

- (BOOL)merge:(rvGEModifier *)merge {
    return NO;
}

- (void)_setName:(NSString *)name {
    _name = [name copy];
}

@end

@implementation rvGEModifierGroup {
    NSMutableArray<rvGEModifier *> *mModifiers;
}

- (instancetype)init {
    self = [super initWithName:@"Group" window:nil];
    if (self) {
        mModifiers = [NSMutableArray array];
    }
    return self;
}

- (NSArray<rvGEModifier *> *)modifiers {
    return [mModifiers copy];
}

- (BOOL)append:(rvGEModifier *)mod {
    // All modifiers must be the same type
    NSAssert( !mModifiers.count || [mod.name ud_iequals:mModifiers[0].name], @"a group's modifiers are of one kind" );

    if ( !mModifiers.count ) {
        [self _setName:mod.name];
    }

    [mModifiers addObject:mod];

    return YES;
}

- (BOOL)isValid {
    for ( rvGEModifier *mod in mModifiers ) {
        if ( ![mod isValid] ) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)apply {
    for ( rvGEModifier *mod in mModifiers ) {
        [mod apply];
    }

    return YES;
}

- (BOOL)undo {
    for ( rvGEModifier *mod in mModifiers ) {
        [mod undo];
    }

    return YES;
}

- (BOOL)canMerge:(rvGEModifier *)mergebase {
    if ( ![mergebase isKindOfClass:[rvGEModifierGroup class]] ) {
        return NO;
    }
    rvGEModifierGroup *merge = (rvGEModifierGroup *)mergebase;

    if ( mModifiers.count != merge->mModifiers.count ) {
        return NO;
    }

    // Double check the merge is possible
    for ( NSUInteger i = 0; i < mModifiers.count; i ++ ) {
        if ( mModifiers[i].window != merge->mModifiers[i].window ) {
            return NO;
        }

        if ( ![mModifiers[i].name ud_iequals:merge->mModifiers[i].name] ) {
            return NO;
        }

        if ( ![mModifiers[i] canMerge:merge->mModifiers[i]] ) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)merge:(rvGEModifier *)mergebase {
    rvGEModifierGroup *merge = (rvGEModifierGroup *)mergebase;

    // Double check the merge is possible
    for ( NSUInteger i = 0; i < mModifiers.count; i ++ ) {
        [mModifiers[i] merge:merge->mModifiers[i]];
    }

    return YES;
}

@end

@implementation rvGEMoveModifier {
    idRectangle mNewRect;
    idRectangle mOldRect;
}

- (instancetype)initWithName:(NSString *)name window:(idWindow *)window x:(float)x y:(float)y {
    self = [super initWithName:name window:window];
    if (self) {
        mOldRect = self.wrapper.clientRect;
        mNewRect.x = mOldRect.x + x;
        mNewRect.y = mOldRect.y + y;
        mNewRect.w = mOldRect.w;
        mNewRect.h = mOldRect.h;
    }
    return self;
}

- (BOOL)canMerge:(rvGEModifier *)merge {
    return YES;
}

- (BOOL)merge:(rvGEModifier *)mergebase {
    rvGEMoveModifier *merge = (rvGEMoveModifier *)mergebase;

    mNewRect = merge->mNewRect;

    return YES;
}

- (BOOL)apply {
    [self.wrapper setRect:mNewRect];

    return YES;
}

- (BOOL)undo {
    [self.wrapper setRect:mOldRect];

    return YES;
}

- (BOOL)isValid {
    if ( ![self.window getParent] ) {
        return NO;
    }

    return YES;
}

@end

@implementation rvGESizeModifier {
    idRectangle mNewRect;
    idRectangle mOldRect;
}

- (instancetype)initWithName:(NSString *)name window:(idWindow *)window l:(float)l t:(float)t r:(float)r b:(float)b {
    self = [super initWithName:name window:window];
    if (self) {
        mOldRect = self.wrapper.clientRect;
        mNewRect.x = mOldRect.x + l;
        mNewRect.y = mOldRect.y + t;
        mNewRect.w = mOldRect.w + r - l;
        mNewRect.h = mOldRect.h + b - t;
    }
    return self;
}

- (BOOL)canMerge:(rvGEModifier *)merge {
    return YES;
}

- (BOOL)merge:(rvGEModifier *)mergebase {
    rvGESizeModifier *merge = (rvGESizeModifier *)mergebase;

    mNewRect = merge->mNewRect;

    return YES;
}

- (BOOL)apply {
    [self.wrapper setRect:mNewRect];

    return YES;
}

- (BOOL)undo {
    [self.wrapper setRect:mOldRect];

    return YES;
}

- (BOOL)isValid {
    if ( ![self.window getParent] ) {
        return NO;
    }

    return YES;
}

@end

@implementation rvGEHideModifier {
    idWindow *mParent;
    BOOL mHide;
    BOOL mUndoHide;
}

- (instancetype)initWithName:(NSString *)name window:(idWindow *)window hide:(BOOL)hide {
    self = [super initWithName:name window:window];
    if (self) {
        mParent = nil;
        mHide = hide;
        mUndoHide = self.wrapper.hidden;

        // If unhiding then find any parent window along the way that may be hidden and prevent
        // this window from being visible
        if ( !hide ) {
            mParent = self.window;
            while ( nil != (mParent = [mParent getParent]) ) {
                if ( [rvGEWindowWrapper wrapperOf:mParent].hidden ) {
                    break;
                }
            }
        }
    }
    return self;
}

/*
================
rvGEHideModifier::Apply

Apply the hide modifier by setting the visible state of the wrapper window
================
*/
- (BOOL)apply {
    self.wrapper.hidden = mHide;

    if ( mParent ) {
        [rvGEWindowWrapper wrapperOf:mParent].hidden = mHide;
    }

    return YES;
}

/*
================
rvGEHideModifier::Undo

Undo the hide modifier by setting the undo visible state of the wrapper window
================
*/
- (BOOL)undo {
    self.wrapper.hidden = mUndoHide;

    if ( mParent ) {
        [rvGEWindowWrapper wrapperOf:mParent].hidden = mUndoHide;
    }

    return YES;
}

@end

@implementation rvGEStateModifier {
    idDict *mDict;
    idDict *mUndoDict;
}

- (instancetype)initWithName:(NSString *)name window:(idWindow *)window dict:(idDict *)dict {
    self = [super initWithName:name window:window];
    if (self) {
        mDict = [dict copy];

        // Make a copy of the current dictionary
        mUndoDict = [self.wrapper.stateDict copy];
    }
    return self;
}

/*
================
rvGEStateModifier::Apply

Applys the new state dictionary to the window
================
*/
- (BOOL)apply {
    return [self setState:mDict];
}

/*
================
rvGEStateModifier::Undo

Applies the undo dictionary to the window
================
*/
- (BOOL)undo {
    return [self setState:mUndoDict];
}

/*
================
rvGEStateModifier::Apply

Applys the given dictionary to the window
================
*/
- (BOOL)setState:(idDict *)dict {
    [self.wrapper setState:dict];

    return YES;
}

@end

@implementation rvGEScriptsModifier {
    idDict *mVariables, *mScripts;
    idDict *mUndoVariables, *mUndoScripts;
}

- (instancetype)initWithName:(NSString *)name window:(idWindow *)window variables:(idDict *)variables scripts:(idDict *)scripts {
    self = [super initWithName:name window:window];
    if (self) {
        mVariables = [variables copy];
        mScripts = [scripts copy];
        mUndoVariables = [self.wrapper.variableDict copy];
        mUndoScripts = [self.wrapper.scriptDict copy];
    }
    return self;
}

static void UDCopyDict(idDict *from, idDict *to) {
    [to clear];
    for (int i = 0; i < [from numKeyVals]; i++) {
        [to set:[from keyAtIndex:i] value:[from valueAtIndex:i]];
    }
}

- (BOOL)apply {
    UDCopyDict(mVariables, self.wrapper.variableDict);
    UDCopyDict(mScripts, self.wrapper.scriptDict);
    return YES;
}

- (BOOL)undo {
    UDCopyDict(mUndoVariables, self.wrapper.variableDict);
    UDCopyDict(mUndoScripts, self.wrapper.scriptDict);
    return YES;
}

@end

@implementation rvGEModifierStack {
    NSMutableArray<rvGEModifier *> *mModifiers;
    int mCurrentModifier;
    BOOL mMergeBlock;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        mModifiers = [NSMutableArray array];
        mCurrentModifier = -1;
        mMergeBlock = NO;     // (the engine's is not set)
    }
    return self;
}

- (void)reset {
    [mModifiers removeAllObjects];
    mCurrentModifier = -1;    // (the engine's is left as it was)
    [self.undoManager removeAllActionsWithTarget:self];
}

- (void)_changed {
    id target = self.target;
    if (target != nil && self.action != NULL && [target respondsToSelector:self.action]) {
        ((void (*)(id, SEL, id))[target methodForSelector:self.action])(target, self.action, self);
    }
}

- (BOOL)append:(rvGEModifier *)modifier {
    // TODO: Add the modifier and clear all redo modifiers
    if ( ![modifier isValid] ) {
        return NO;
    }

    while ( mCurrentModifier < (int)mModifiers.count - 1 ) {
        [mModifiers removeLastObject];
    }

    if ( !mMergeBlock && mModifiers.count ) {
        rvGEModifier *top = mModifiers.lastObject;

        // See if the two modifiers can merge
        if ( top.window == modifier.window &&
             [top.name ud_iequals:modifier.name] &&
             [top canMerge:modifier] ) {
            // Merge the two modifiers
            if ( [top merge:modifier] ) {
                [top apply];
                [self _changed];
                return YES;
            }
        }
    }

    [mModifiers addObject:modifier];
    mCurrentModifier = (int)mModifiers.count - 1;
    [modifier apply];

    mMergeBlock = NO;

    NSUndoManager *undoManager = self.undoManager;
    if ( undoManager != nil ) {
        [undoManager registerUndoWithTarget:self selector:@selector(_undoFromManager:) object:modifier];
        [undoManager setActionName:modifier.name];
    }

    [self _changed];
    return YES;
}

- (BOOL)undo {
    if ( mCurrentModifier < 0 ) {
        return NO;
    }

    [mModifiers[(NSUInteger)mCurrentModifier] undo];
    mCurrentModifier--;

    [self _changed];
    return YES;
}

- (BOOL)redo {
    if ( mCurrentModifier + 1 < (int)mModifiers.count ) {
        mCurrentModifier++;
        [mModifiers[(NSUInteger)mCurrentModifier] apply];
    }

    [self _changed];
    return YES;
}

/// The undo manager's Undo of @a modifier: the stack's, its Redo registered.
- (void)_undoFromManager:(rvGEModifier *)modifier {
    [self undo];
    [self.undoManager registerUndoWithTarget:self selector:@selector(_redoFromManager:) object:modifier];
    [self.undoManager setActionName:modifier.name];
}

- (void)_redoFromManager:(rvGEModifier *)modifier {
    [self redo];
    [self.undoManager registerUndoWithTarget:self selector:@selector(_undoFromManager:) object:modifier];
    [self.undoManager setActionName:modifier.name];
}

- (BOOL)canRedo {
    return mCurrentModifier < (int)mModifiers.count - 1;
}

- (BOOL)canUndo {
    return mCurrentModifier >= 0;
}

- (void)blockNextMerge {
    mMergeBlock = YES;
}

- (rvGEModifier *)undoModifier {
    return [self canUndo] ? mModifiers[(NSUInteger)mCurrentModifier] : nil;
}

- (rvGEModifier *)redoModifier {
    return [self canRedo] ? mModifiers[(NSUInteger)mCurrentModifier + 1] : nil;
}

@end
