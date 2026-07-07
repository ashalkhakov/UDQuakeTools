/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEditorViewModel.m — UI-facing view model for GUI editor workflows.
 */

#import "UDGuiEditorViewModel.h"

@interface UDGuiEditorViewModel ()
@property (nonatomic, readwrite, strong) UDGuiEditorService *service;
@end

@implementation UDGuiEditorViewModel

- (instancetype)init {
    self = [self initWithService:[[UDGuiEditorService alloc] init]];
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

@synthesize selectedWindow = _selectedWindow;

- (instancetype)initWithService:(UDGuiEditorService *)service {
    NSParameterAssert(service != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _service = service;
    return self;
}

- (NSArray<UDGuiWindowNode *> *)rootWindows {
    return [self.service.document.rootWindows copy];
}

- (NSArray<UDGuiWindowNode *> *)childrenOfWindow:(UDGuiWindowNode *)window {
    if (!window) {
        return [self rootWindows];
    }
    return [window.children copy];
}

- (NSArray<UDGuiProperty *> *)selectedWindowProperties {
    if (!self.selectedWindow) {
        return @[];
    }
    return [self.selectedWindow.properties copy];
}

- (NSString *)selectedWindowBreadcrumb {
    if (!self.selectedWindow) {
        return @"No selection";
    }

    NSMutableArray<NSString *> *segments = [NSMutableArray array];
    UDGuiWindowNode *cursor = self.selectedWindow;
    while (cursor) {
        [segments addObject:[NSString stringWithFormat:@"%@ %@", cursor.className, cursor.name]];
        cursor = cursor.parent;
    }

    NSArray<NSString *> *reversed = [[segments reverseObjectEnumerator] allObjects];
    return [reversed componentsJoinedByString:@" / "];
}

- (void)applyPropertyEditForSelectedWindowWithKey:(NSString *)key value:(NSString *)value {
    if (!self.selectedWindow || key.length == 0 || value == nil) {
        return;
    }
    [self.service updatePropertyForWindow:self.selectedWindow key:key value:value];
}

- (void)removePropertyFromSelectedWindowWithKey:(NSString *)key {
    if (!self.selectedWindow || key.length == 0) {
        return;
    }
    [self.service removePropertyForWindow:self.selectedWindow key:key];
}

- (nullable UDGuiWindowNode *)addChildWindowToSelectedWindowWithClassName:(NSString *)className
                                                                      name:(NSString *)name {
    if (className.length == 0 || name.length == 0) {
        return nil;
    }

    UDGuiWindowNode *newNode = [[UDGuiWindowNode alloc] initWithClassName:className name:name];
    UDGuiWindowNode *parent = self.selectedWindow;
    BOOL parentInDocument = NO;
    if (parent) {
        parentInDocument = parent.parent != nil || [self.service.document indexOfRootWindow:parent] != NSNotFound;
    }

    if (parentInDocument) {
        [self.service addWindow:newNode toParent:parent atIndex:parent.children.count];
    } else {
        self.selectedWindow = nil;
        [self.service addWindow:newNode toParent:nil atIndex:self.service.document.rootWindows.count];
    }
    self.selectedWindow = newNode;
    return newNode;
}

- (void)deleteSelectedWindow {
    if (!self.selectedWindow) {
        return;
    }

    UDGuiWindowNode *deleted = self.selectedWindow;
    UDGuiWindowNode *fallback = deleted.parent;
    [self.service removeWindow:deleted];
    self.selectedWindow = fallback;
}

@end
