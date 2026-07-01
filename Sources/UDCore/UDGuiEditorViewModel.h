/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEditorViewModel.h — UI-facing view model for GUI editor workflows.
 */

#import <Foundation/Foundation.h>

#import "UDGuiEditorService.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiEditorViewModel : NSObject

@property (nonatomic, readonly, strong) UDGuiEditorService *service;
@property (nullable, nonatomic, strong) UDGuiWindowNode *selectedWindow;

- (instancetype)initWithService:(UDGuiEditorService *)service NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<UDGuiWindowNode *> *)rootWindows;
- (NSArray<UDGuiWindowNode *> *)childrenOfWindow:(nullable UDGuiWindowNode *)window;
- (NSArray<UDGuiProperty *> *)selectedWindowProperties;
- (NSString *)selectedWindowBreadcrumb;

- (void)applyPropertyEditForSelectedWindowWithKey:(NSString *)key value:(NSString *)value;
- (void)removePropertyFromSelectedWindowWithKey:(NSString *)key;

- (nullable UDGuiWindowNode *)addChildWindowToSelectedWindowWithClassName:(NSString *)className
                                                                      name:(NSString *)name;
- (void)deleteSelectedWindow;

@end

NS_ASSUME_NONNULL_END
