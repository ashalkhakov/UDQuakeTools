/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idWindowEditorWrapper.h — the GUI editor's wrapper of a window, as a
 * window's parse fills it while its manager is editing (the engine's
 * "guied_wrapper" variable; rvGEWindowWrapper, the GUI editor's, adopts
 * this): the UI needs nothing of the editor's but this.
 */

#import <Foundation/Foundation.h>

@class idWindow, idDict;

NS_ASSUME_NONNULL_BEGIN

@protocol idWindowEditorWrapper <NSObject>
/// A wrapper for @a window, hung on it (its guiedWrapper).
- (instancetype)initForWindow:(idWindow *)window;
/// The window's text as the editor keeps it: its state keys, its
/// variables, its scripts.
@property (nonatomic, strong, readonly) idDict *stateDict;
@property (nonatomic, strong, readonly) idDict *variableDict;
@property (nonatomic, strong, readonly) idDict *scriptDict;
- (void)setStateKey:(NSString *)key value:(NSString *)value update:(BOOL)update;
/// After the window is parsed.
- (void)finish;
@end

NS_ASSUME_NONNULL_END
