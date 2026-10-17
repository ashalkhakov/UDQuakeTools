/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEWindowWrapper.h — the GUI editor's side of a window
 * (tools/guied/GEWindowWrapper.h, GEWindowWrapper.cpp), ported: the text
 * the window was parsed from, kept as the editor writes it back (its
 * state keys, its variables, its scripts), its rectangle on the screen, and
 * what the editor marks it (selected, hidden, deleted, expanded).
 *
 * idWindow::Parse makes one for every window while its manager is editing
 * (com_editors & EDITOR_GUI). The engine hangs it on the window as a
 * "guied_wrapper" variable holding its address, for want of a field; here
 * the window holds it (idWindow's guiedWrapper), the wrapper its window
 * weakly.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"

@class idWindow, idDict;

NS_ASSUME_NONNULL_BEGIN

/// rvGEWindowWrapper::EWindowType
typedef NS_ENUM(int, rvGEWindowType) {
    WT_UNKNOWN,
    WT_NORMAL,
    WT_EDIT,
    WT_HTML,
    WT_CHOICE,
    WT_SLIDER,
    WT_BIND,
    WT_LIST,
    WT_RENDER,
    WT_TRANSITION
};

@interface rvGEWindowWrapper : NSObject

/// A wrapper for @a window, hung on it; its type from the window's class
/// where it is one of the item windows'.
- (instancetype)initWithWindow:(idWindow *)window type:(rvGEWindowType)type;

/// GetWrapper: @a window's wrapper, nil when it has none.
+ (nullable rvGEWindowWrapper *)wrapperOf:(nullable idWindow *)window;

@property (nonatomic, weak, readonly, nullable) idWindow *window;

/// The window's text, as the editor keeps it: its state keys ("rect" →
/// "0,0,640,480") and its variables ("float\t\"x\"" → the rest) in the
/// order read; its scripts ("onAction", "onEvent name", "onTime 100") as
/// their braced text.
@property (nonatomic, strong, readonly) idDict *stateDict;
@property (nonatomic, strong, readonly) idDict *variableDict;
@property (nonatomic, strong, readonly) idDict *scriptDict;

/// The rect, in its parent's coordinates and on the screen (the 640x480).
@property (nonatomic, readonly) idRectangle clientRect;
@property (nonatomic, readonly) idRectangle screenRect;

@property (nonatomic) rvGEWindowType windowType;

- (int)childCount;
- (int)depth;
- (nullable idWindow *)childAtIndex:(int)index;

- (void)setRect:(idRectangle)rect;
- (void)setState:(idDict *)dict;
- (void)setStateKey:(NSString *)key value:(NSString *)value update:(BOOL)update;
- (void)deleteStateKey:(NSString *)key;

@property (nonatomic) BOOL flippedHorz;
@property (nonatomic) BOOL flippedVert;
@property (nonatomic) BOOL hidden;
@property (nonatomic) BOOL deleted;
@property (nonatomic) BOOL selected;
@property (nonatomic, readonly) BOOL expanded;
- (BOOL)canHaveChildren;
/// CanMoveAndSize: its rect is numbers, not an expression.
- (BOOL)canMoveAndSize;

- (BOOL)expand;
- (BOOL)collapse;

/// The topmost window under ( @a x, @a y ) on the screen, this one or
/// one of its children; the hidden and deleted not, if @a visibleOnly.
- (nullable idWindow *)windowFromPointX:(float)x y:(float)y visibleOnly:(BOOL)visibleOnly;

/// After the window is parsed: its visibility and rect read.
- (void)finish;

+ (rvGEWindowType)windowTypeFromString:(NSString *)string;
+ (NSString *)stringFromWindowType:(rvGEWindowType)type;

@end

/// IsExpression (tools/guied/guied.cpp): whether @a s is an expression
/// rather than numbers, commas and signs.
BOOL rvGE_IsExpression(NSString *s);

NS_ASSUME_NONNULL_END
