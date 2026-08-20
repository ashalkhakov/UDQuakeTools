/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDOutlinePaneController.m — Outline pane controller for the GUI editor.
 */

#import "UDOutlinePaneController.h"
#import "UDGuiEdDocument.h"

#import "UDGuiEditorViewModel.h"
#import "UDGuiModel.h"

@implementation UDOutlinePaneController

@synthesize view = _view;
@synthesize outlineView = _outlineView;

- (instancetype)init {
    self = [super init];
    if (self) {
#ifdef GNUSTEP
        [NSBundle loadNibNamed:@"UDOutlinePane" owner:self];
#else
        [[NSBundle mainBundle] loadNibNamed:@"UDOutlinePane" owner:self topLevelObjects:nil];
#endif
    }
    return self;
}

// MARK: - Private helpers

- (nullable UDGuiWindowNode *)windowNodeForOutlineItem:(nullable id)item {
    return [item isKindOfClass:[UDGuiWindowNode class]] ? (UDGuiWindowNode *)item : nil;
}

- (UDGuiWindowNode *)createWindowWithPrefix:(NSString *)prefix index:(NSUInteger)index {
    return [UDGuiWindowNode windowNodeWithClassName:@"windowDef"
                                               name:[NSString stringWithFormat:@"%@%lu", prefix, (unsigned long)index]];
}

- (void)addWindowWithPrefix:(NSString *)prefix toParent:(nullable UDGuiWindowNode *)parent {
    NSArray<UDGuiWindowNode *> *siblings = parent
        ? parent.children
        : self.context.ownerDocument.viewModel.rootWindows;
    NSUInteger insertionIndex = siblings.count;
    UDGuiWindowNode *window   = [self createWindowWithPrefix:prefix index:insertionIndex + 1];
    [self.context.ownerDocument.editorService addWindow:window toParent:parent atIndex:insertionIndex];
    self.context.ownerDocument.viewModel.selectedWindow = window;
    [self.context notifyModelChangedAndRefresh];
}

- (void)restoreOutlineSelection {
    UDGuiWindowNode *selectedWindow = self.context.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) {
        [self.outlineView deselectAll:nil];
        return;
    }
    NSInteger row = [self.outlineView rowForItem:selectedWindow];
    if (row >= 0) {
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [self.outlineView scrollRowToVisible:row];
    }
}

// MARK: - UDOutlinePaneController public interface

- (void)refreshOutlinePane {
    [self.outlineView reloadData];
    [self restoreOutlineSelection];
}

// MARK: - Actions

- (IBAction)addRootWindow:(id)sender {
    (void)sender;
    [self addWindowWithPrefix:@"Window" toParent:nil];
}

- (IBAction)addChildWindow:(id)sender {
    (void)sender;
    UDGuiWindowNode *selectedWindow = self.context.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) { return; }
    [self addWindowWithPrefix:@"Child" toParent:selectedWindow];
}

- (IBAction)deleteSelectedWindow:(id)sender {
    (void)sender;
    UDGuiWindowNode *selectedWindow = self.context.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) { return; }
    [self.context.ownerDocument.editorService removeWindow:selectedWindow];
    self.context.ownerDocument.viewModel.selectedWindow = selectedWindow.parent;
    [self.context notifyModelChangedAndRefresh];
}

// MARK: - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    (void)outlineView;
    NSArray<UDGuiWindowNode *> *children = [self.context.ownerDocument.viewModel childrenOfWindow:[self windowNodeForOutlineItem:item]];
    return (NSInteger)children.count;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [self outlineView:outlineView numberOfChildrenOfItem:item] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    (void)outlineView;
    NSArray<UDGuiWindowNode *> *children = [self.context.ownerDocument.viewModel childrenOfWindow:[self windowNodeForOutlineItem:item]];
    if (index < 0 || index >= (NSInteger)children.count) { return nil; }
    return [children objectAtIndex:(NSUInteger)index];
}

- (nullable id)outlineView:(NSOutlineView *)outlineView
  objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
                     byItem:(nullable id)item {
    (void)outlineView;
    UDGuiWindowNode *window = [self windowNodeForOutlineItem:item];
    if (!window) { return @""; }
    if ([tableColumn.identifier isEqualToString:@"node"]) {
        return [NSString stringWithFormat:@"%@ %@", window.className, window.name];
    }
    return @"";
}

// MARK: - NSOutlineViewDelegate

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    NSInteger row = self.outlineView.selectedRow;
    UDGuiWindowNode *selectedWindow = row >= 0 ? [self.outlineView itemAtRow:row] : nil;
    self.context.ownerDocument.viewModel.selectedWindow = selectedWindow;
    [self.context refreshFromDocument];
}

- (void)beginEditingSelectedWindowIdentity:(id)sender {
    [self.context beginEditingSelectedWindowIdentity:sender];
}

@end
