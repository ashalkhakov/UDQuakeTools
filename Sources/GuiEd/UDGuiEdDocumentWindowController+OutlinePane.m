/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController+OutlinePane.h"
#import "UDGuiEdDocumentWindowController+Conventions.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
@end

@implementation UDGuiEdDocumentWindowController (OutlinePane)

- (UDGuiWindowNode *)createWindowWithPrefix:(NSString *)prefix index:(NSUInteger)index {
    return [UDGuiWindowNode windowNodeWithClassName:@"windowDef"
                                               name:[NSString stringWithFormat:@"%@%lu", prefix, (unsigned long)index]];
}

- (void)addWindowWithPrefix:(NSString *)prefix toParent:(UDGuiWindowNode *)parent {
    NSArray<UDGuiWindowNode *> *siblings = parent ? parent.children : self.ownerDocument.viewModel.rootWindows;
    NSUInteger insertionIndex = siblings.count;
    UDGuiWindowNode *window = [self createWindowWithPrefix:prefix index:insertionIndex + 1];
    [self.ownerDocument.editorService addWindow:window toParent:parent atIndex:insertionIndex];
    self.ownerDocument.viewModel.selectedWindow = window;
    [self ud_notifyModelDidChangeAndRefresh];
}

- (void)refreshOutlinePane {
    [self.outlineView reloadData];
    [self restoreOutlineSelection];
}

- (void)restoreOutlineSelection {
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;
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

- (void)syncSelectionToViewModel:(UDGuiWindowNode *)selectedWindow {
    self.ownerDocument.viewModel.selectedWindow = selectedWindow;
}

- (UDGuiWindowNode *)windowNodeForOutlineItem:(id)item {
    return [item isKindOfClass:[UDGuiWindowNode class]] ? item : nil;
}

- (IBAction)addRootWindow:(id)sender {
    (void)sender;
    [self addWindowWithPrefix:@"Window" toParent:nil];
}

- (IBAction)addChildWindow:(id)sender {
    (void)sender;
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) {
        return;
    }

    [self addWindowWithPrefix:@"Child" toParent:selectedWindow];
}

- (IBAction)deleteSelectedWindow:(id)sender {
    (void)sender;
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) {
        return;
    }

    [self.ownerDocument.editorService removeWindow:selectedWindow];
    self.ownerDocument.viewModel.selectedWindow = selectedWindow.parent;
    [self ud_notifyModelDidChangeAndRefresh];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    (void)outlineView;
    NSArray<UDGuiWindowNode *> *children = [self.ownerDocument.viewModel childrenOfWindow:[self windowNodeForOutlineItem:item]];
    return (NSInteger)children.count;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    (void)outlineView;
    return [self outlineView:outlineView numberOfChildrenOfItem:item] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    (void)outlineView;
    NSArray<UDGuiWindowNode *> *children = [self.ownerDocument.viewModel childrenOfWindow:[self windowNodeForOutlineItem:item]];
    if (index < 0 || index >= (NSInteger)children.count) {
        return nil;
    }
    return [children objectAtIndex:(NSUInteger)index];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    (void)outlineView;
    UDGuiWindowNode *window = [self windowNodeForOutlineItem:item];
    if (!window) {
        return @"";
    }

    if ([tableColumn.identifier isEqualToString:@"node"]) {
        return [NSString stringWithFormat:@"%@ %@", window.className, window.name];
    }
    return @"";
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    NSInteger row = self.outlineView.selectedRow;
    UDGuiWindowNode *selectedWindow = row >= 0 ? [self.outlineView itemAtRow:row] : nil;
    [self syncSelectionToViewModel:selectedWindow];
    [self refreshFromDocument];
}

@end
