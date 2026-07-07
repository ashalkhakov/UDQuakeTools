/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEditorService.m — GUI editing operations with undo/redo support.
 */

#import "UDGuiEditorService.h"


@interface UDGuiEditorService ()
@property (nonatomic, readwrite, strong) UDGuiDocument *document;
@property (nonatomic, readwrite, strong) NSUndoManager *undoManager;
- (void)registerUndoAction:(void (^)(void))action;
@end

@implementation UDGuiEditorService

- (instancetype)init {
    self = [self initWithDocument:[[UDGuiDocument alloc] initWithSourceVirtualPath:@"empty"] undoManager:nil];
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithDocument:(UDGuiDocument *)document undoManager:(NSUndoManager *)undoManager {
    NSParameterAssert(document != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _document = document;
    _undoManager = undoManager ?: [[NSUndoManager alloc] init];
    // Use explicit per-operation grouping so unit tests don't collapse multiple edits into one undo step.
    [_undoManager setGroupsByEvent:NO];
    return self;
}

- (void)registerUndoAction:(void (^)(void))action {
    if (!action) {
        return;
    }

    BOOL openedGroup = NO;
    if (self.undoManager.groupingLevel == 0) {
        [self.undoManager beginUndoGrouping];
        openedGroup = YES;
    }

    action();

    if (openedGroup) {
        [self.undoManager endUndoGrouping];
    }
}

- (void)replaceDocument:(UDGuiDocument *)document {
    NSParameterAssert(document != nil);

    UDGuiDocument *oldDocument = self.document;
    self.document = document;

    [self registerUndoAction:^{
        [[self.undoManager prepareWithInvocationTarget:self] replaceDocument:oldDocument];
    }];
}

- (void)updatePropertyForWindow:(UDGuiWindowNode *)window
                            key:(NSString *)key
                          value:(NSString *)value {
    NSParameterAssert(window != nil);
    NSParameterAssert(key.length > 0);
    NSParameterAssert(value != nil);

    UDGuiProperty *existing = [window propertyForKey:key];
    NSString *oldValue = existing ? existing.value : nil;

    [window setPropertyValue:value forKey:key];

    if (oldValue) {
        [self registerUndoAction:^{
            [[self.undoManager prepareWithInvocationTarget:self] updatePropertyForWindow:window key:key value:oldValue];
        }];
    } else {
        [self registerUndoAction:^{
            [[self.undoManager prepareWithInvocationTarget:self] removePropertyForWindow:window key:key];
        }];
    }
}

- (void)updateWindow:(UDGuiWindowNode *)window className:(NSString *)className {
    NSParameterAssert(window != nil);
    NSParameterAssert(className.length > 0);

    NSString *oldClassName = window.className;
    if ([oldClassName isEqualToString:className]) {
        return;
    }

    window.className = className;
    [self registerUndoAction:^{
        [[self.undoManager prepareWithInvocationTarget:self] updateWindow:window className:oldClassName];
    }];
}

- (void)updateWindow:(UDGuiWindowNode *)window name:(NSString *)name {
    NSParameterAssert(window != nil);
    NSParameterAssert(name.length > 0);

    NSString *oldName = window.name;
    if ([oldName isEqualToString:name]) {
        return;
    }

    window.name = name;
    [self registerUndoAction:^{
        [[self.undoManager prepareWithInvocationTarget:self] updateWindow:window name:oldName];
    }];
}

- (void)renamePropertyForWindow:(UDGuiWindowNode *)window
                         fromKey:(NSString *)oldKey
                           toKey:(NSString *)newKey
                           value:(NSString *)value {
    NSParameterAssert(window != nil);
    NSParameterAssert(oldKey.length > 0);
    NSParameterAssert(newKey.length > 0);
    NSParameterAssert(value != nil);

    if ([oldKey isEqualToString:newKey]) {
        [self updatePropertyForWindow:window key:newKey value:value];
        return;
    }

    UDGuiProperty *existing = [window propertyForKey:oldKey];
    if (!existing) {
        [self updatePropertyForWindow:window key:newKey value:value];
        return;
    }

    NSString *oldValue = existing.value;
    [window removePropertyForKey:oldKey];
    [window setPropertyValue:value forKey:newKey];
    [self registerUndoAction:^{
        [[self.undoManager prepareWithInvocationTarget:self] renamePropertyForWindow:window fromKey:newKey toKey:oldKey value:oldValue];
    }];
}

- (void)removePropertyForWindow:(UDGuiWindowNode *)window key:(NSString *)key {
    NSParameterAssert(window != nil);
    NSParameterAssert(key.length > 0);

    UDGuiProperty *existing = [window propertyForKey:key];
    if (!existing) {
        return;
    }

    [window removePropertyForKey:key];
    [self registerUndoAction:^{
        [[self.undoManager prepareWithInvocationTarget:self] updatePropertyForWindow:window key:key value:existing.value];
    }];
}

- (void)addWindow:(UDGuiWindowNode *)window toParent:(UDGuiWindowNode *)parent atIndex:(NSUInteger)index {
    NSParameterAssert(window != nil);

    if (parent) {
        [parent insertChild:window atIndex:index];
    } else {
        [self.document insertRootWindow:window atIndex:index];
    }

    [self registerUndoAction:^{
        [[self.undoManager prepareWithInvocationTarget:self] removeWindow:window];
    }];
}

- (void)removeWindow:(UDGuiWindowNode *)window {
    NSParameterAssert(window != nil);

    UDGuiWindowNode *parent = window.parent;
    NSUInteger index = NSNotFound;

    if (parent) {
        index = [parent indexOfChild:window];
        [parent removeChild:window];
    } else {
        index = [self.document indexOfRootWindow:window];
        [self.document removeRootWindow:window];
    }

    if (index == NSNotFound) {
        return;
    }

    [self registerUndoAction:^{
        [[self.undoManager prepareWithInvocationTarget:self] addWindow:window toParent:parent atIndex:index];
    }];
}

- (void)moveWindow:(UDGuiWindowNode *)window toNewParent:(UDGuiWindowNode *)newParent atIndex:(NSUInteger)index {
    NSParameterAssert(window != nil);

    UDGuiWindowNode *oldParent = window.parent;
    NSUInteger oldIndex = oldParent ? [oldParent indexOfChild:window] : [self.document indexOfRootWindow:window];

    if (oldParent) {
        [oldParent removeChild:window];
    } else {
        [self.document removeRootWindow:window];
    }

    if (newParent) {
        [newParent insertChild:window atIndex:index];
    } else {
        [self.document insertRootWindow:window atIndex:index];
    }

    [self registerUndoAction:^{
        [[self.undoManager prepareWithInvocationTarget:self] moveWindow:window toNewParent:oldParent atIndex:oldIndex];
    }];
}

- (void)updateCommandsForEventHandlerAtIndex:(NSUInteger)handlerIndex
                                    onWindow:(UDGuiWindowNode *)window
                                 newCommands:(NSArray<UDGuiScriptCommand *> *)newCommands {
    NSParameterAssert(window != nil);
    NSParameterAssert(newCommands != nil);

    NSArray<UDGuiEventHandler *> *handlers = window.eventHandlers;
    if (handlerIndex >= handlers.count) {
        return;
    }

    UDGuiEventHandler *handler = [handlers objectAtIndex:handlerIndex];
    NSArray<UDGuiScriptCommand *> *oldCommands = handler.commands;

    UDGuiEventHandler *newHandler = [handler deepCopy];
    [newHandler replaceCommandsWithArray:newCommands];

    [window replaceEventHandlerAtIndex:handlerIndex withEventHandler:newHandler];

    [self registerUndoAction:^{
        [[self.undoManager prepareWithInvocationTarget:self] updateCommandsForEventHandlerAtIndex:handlerIndex
                                                                                         onWindow:window
                                                                                      newCommands:oldCommands];
    }];
}

@end
