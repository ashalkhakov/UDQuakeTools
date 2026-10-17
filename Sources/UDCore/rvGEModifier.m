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

@implementation rvGEInsertModifier {
    idWindow *mParent;
    idWindow *mBefore;
    idRectangle mRect;
    idWindow *mUndoParent;
    idWindow *mUndoBefore;
    idRectangle mUndoRect;
}

- (instancetype)initWithName:(NSString *)name window:(idWindow *)window parent:(idWindow *)parent before:(idWindow *)before {
    self = [super initWithName:name window:window];
    if (self) {
        mParent = parent;
        mBefore = before;

        NSAssert( mParent, @"a parent to insert in" );

        mUndoParent = [window getParent];
        mUndoBefore = nil;
        mUndoRect = self.wrapper.clientRect;
        mRect = self.wrapper.clientRect;

        // Find the child window the window being inserted is before
        if ( mUndoParent ) {
            int index;
            rvGEWindowWrapper *pwrapper;

            pwrapper = [rvGEWindowWrapper wrapperOf:mUndoParent];
            index = [mUndoParent getChildIndex:self.window];

            if ( index + 1 < [pwrapper childCount] ) {
                mUndoBefore = [pwrapper childAtIndex:index + 1];
            }
        }

        // Since rectangles are relative to the parent rectangle we need to figure
        // out the new x and y coordinate as if this window were a child
        rvGEWindowWrapper *parentWrapper;
        parentWrapper = [rvGEWindowWrapper wrapperOf:mParent];
        mRect.x = self.wrapper.screenRect.x - parentWrapper.screenRect.x;
        mRect.y = self.wrapper.screenRect.y - parentWrapper.screenRect.y;
    }
    return self;
}

/*
================
rvGEInsertModifier::Apply

Apply the insert modifier by removing the child from its original parent and
inserting it as a child of the new parent
================
*/
- (BOOL)apply {
    if ( mUndoParent ) {
        [mUndoParent removeChild:self.window];
    }

    [mParent insertChild:self.window before:mBefore];
    [self.wrapper setRect:mRect];

    return YES;
}

/*
================
rvGEInsertModifier::Undo

Undo the insert modifier by removing the window from the parent it was
added to and re-inserting it back into its original parent
================
*/
- (BOOL)undo {
    [mParent removeChild:self.window];

    if ( mUndoParent ) {
        [mUndoParent insertChild:self.window before:mUndoBefore];
        [self.wrapper setRect:mUndoRect];
    }

    return YES;
}

@end

@implementation rvGEDeleteModifier

/*
================
rvGEDeleteModifier::Apply

Apply the delete modifier by setting the deleted flag in the wrapper
================
*/
- (BOOL)apply {
    self.wrapper.deleted = YES;

    return YES;
}

/*
================
rvGEDeleteModifier::Undo

Undo the delete modifier by unsetting the deleted flag in the wrapper
================
*/
- (BOOL)undo {
    self.wrapper.deleted = NO;

    return YES;
}

@end

@implementation rvGEZOrderModifier {
    idWindow *mBefore;
    idWindow *mUndoBefore;
}

- (instancetype)initWithName:(NSString *)name window:(idWindow *)window change:(rvGEZOrderChange)change {
    self = [super initWithName:name window:window];
    if (self) {
        int count;
        int index;
        idWindow *parent;

        parent = [window getParent];
        if ( !parent ) {
            return self;
        }

        count = [parent getChildCount];
        index = [parent getChildIndex:self.window];

        if ( index + 1 >= count ) {
            mUndoBefore = nil;
        } else {
            mUndoBefore = [parent getChild:index + 1];
        }

        switch ( change ) {
            case ZO_FORWARD:
                index += 2;
                break;

            case ZO_BACKWARD:
                if ( index == 0 ) {
                    index = 1;
                } else {
                    index -= 1;
                }
                break;

            case ZO_BACK:
                index = 0;
                break;

            case ZO_FRONT:
                index = count;
                break;
        }

        if ( index >= count ) {
            mBefore = nil;
        } else {
            mBefore = [parent getChild:index];
        }
    }
    return self;
}

- (BOOL)apply {
    idWindow *parent;

    parent = [self.window getParent];
    [parent removeChild:self.window];
    [parent insertChild:self.window before:mBefore];

    return YES;
}

- (BOOL)undo {
    idWindow *parent;

    parent = [self.window getParent];
    [parent removeChild:self.window];
    [parent insertChild:self.window before:mUndoBefore];

    return YES;
}

- (BOOL)isValid {
    if ( ![self.window getParent] ) {
        return NO;
    }

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

- (void)_changed:(nullable rvGEModifier *)modifier {
    _changedModifier = modifier;
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
                [self _changed:top];
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

    [self _changed:modifier];
    return YES;
}

- (BOOL)undo {
    if ( mCurrentModifier < 0 ) {
        return NO;
    }

    rvGEModifier *modifier = mModifiers[(NSUInteger)mCurrentModifier];
    [modifier undo];
    mCurrentModifier--;

    [self _changed:modifier];
    return YES;
}

- (BOOL)redo {
    rvGEModifier *modifier = nil;
    if ( mCurrentModifier + 1 < (int)mModifiers.count ) {
        mCurrentModifier++;
        modifier = mModifiers[(NSUInteger)mCurrentModifier];
        [modifier apply];
    }

    [self _changed:modifier];
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
