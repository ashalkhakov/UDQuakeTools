/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController+DetailPane.h"
#import "UDGuiEdDocumentWindowController+Conventions.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
- (void)updateInspectorPresentationForWindow:(UDGuiWindowNode *)selectedWindow;
@end

@implementation UDGuiEdDocumentWindowController (DetailPane)

- (void)refreshDetailPaneForSelectedWindow {
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;

    [self ud_setTextField:self.breadcrumbLabel fromString:self.ownerDocument.viewModel.selectedWindowBreadcrumb];
    [self ud_setTextField:self.classNameField fromString:selectedWindow.className];
    [self ud_setTextField:self.windowNameField fromString:selectedWindow.name];

    [self updateInspectorPresentationForWindow:selectedWindow];
}

- (IBAction)beginEditingSelectedWindowIdentity:(id)sender {
    (void)sender;
    if (!self.ownerDocument.viewModel.selectedWindow) {
        return;
    }

    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.window makeFirstResponder:self.windowNameField];
        [self.windowNameField selectText:nil];
    }];
}

- (BOOL)isWindowInspectorField:(id)sender {
    return sender == self.classNameField || sender == self.windowNameField;
}

- (void)commitWindowIdentityEdit:(id)sender {
    (void)sender;
    if (self.inspectorSectionTabs.selectedSegment != 0) {
        return;
    }

    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) {
        return;
    }

    if (self.classNameField.stringValue.length > 0) {
        [self.ownerDocument.editorService updateWindow:selectedWindow className:self.classNameField.stringValue];
    }
    if (self.windowNameField.stringValue.length > 0) {
        [self.ownerDocument.editorService updateWindow:selectedWindow name:self.windowNameField.stringValue];
    }

    [self ud_notifyModelDidChangeAndRefresh];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    id field = notification.object;
    if ([self isWindowInspectorField:field]) {
        [self commitWindowIdentityEdit:field];
        return;
    }
}

@end
