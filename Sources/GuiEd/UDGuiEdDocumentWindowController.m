/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEdDocumentWindowController.m
 *
 * Thin orchestration layer: creates and wires collaborator controllers, handles
 * window lifecycle, inspector-section switching, and identity-field commits.
 */

#import "UDGuiEdDocumentWindowController.h"
#import "UDInspectorController.h"
#import "UDEventsController.h"
#import "UDVariablesController.h"
#import "UDOutlinePaneController.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

typedef NS_ENUM(NSInteger, UDGuiInspectorSection) {
    UDGuiInspectorSectionIdentity = 0,
    UDGuiInspectorSectionAttributes,
    UDGuiInspectorSectionSize,
    UDGuiInspectorSectionVariables,
    UDGuiInspectorSectionEvents,
};

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Private extension — structural outlets and collaborators
// ---------------------------------------------------------------------------

@interface UDGuiEdDocumentWindowController ()

// MARK: Collaborators
@property (nonatomic, strong) UDInspectorController   *inspectorController;
@property (nonatomic, strong) UDEventsController      *eventsController;
@property (nonatomic, strong) UDVariablesController   *variablesController;
@property (nonatomic, strong) UDOutlinePaneController *outlinePaneController;

// MARK: Document reference
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;

// MARK: Inspector state
@property (nonatomic, assign) UDGuiInspectorSection activeInspectorSection;

// MARK: Layout / structural outlets
@property (nonatomic, strong) IBOutlet NSView            *editorContainerView;
@property (nonatomic, strong) IBOutlet NSTextField       *statusLabel;
@property (nonatomic, strong) IBOutlet NSTextField       *breadcrumbLabel;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *inspectorSectionTabs;
@property (nonatomic, strong) IBOutlet NSTabView         *inspectorSectionTabView;
@property (nonatomic, strong) IBOutlet NSView            *identityPanelView;
@property (nonatomic, strong) IBOutlet NSView            *attributesPanelView;
@property (nonatomic, strong) IBOutlet NSView            *sizePanelView;
@property (nonatomic, strong) IBOutlet NSView            *variablesPanelView;
@property (nonatomic, strong) IBOutlet NSView            *eventsPanelView;
@property (nonatomic, strong) IBOutlet NSView            *sidebarContainerView;

@end

// ---------------------------------------------------------------------------

@implementation UDGuiEdDocumentWindowController

// MARK: - Init

- (instancetype)initWithDocument:(UDGuiEdDocument *)document {
    self = [super initWithWindowNibName:@"UDGuiEdDocument"];
    if (!self) { return nil; }
    _ownerDocument = document;
    _activeInspectorSection = UDGuiInspectorSectionAttributes;
    return self;
}

// MARK: - UDEditorControllerContext

- (UDGuiEdDocument *)ownerDocument {
    return _ownerDocument;
}

- (void)notifyModelChangedAndRefresh {
    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

// MARK: - Lifecycle

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.delegate = self;

    [self createCollaborators];
    [self embedCollaboratorViews];

    if (self.inspectorSectionTabs) {
        [self.inspectorSectionTabs setSelectedSegment:(NSInteger)self.activeInspectorSection];
    }
    [self.eventsController registerDragTypes];
    [self refreshFromDocument];
}

// MARK: - Collaborator setup and view embedding

- (void)createCollaborators {
    self.inspectorController   = [[UDInspectorController alloc] init];
    self.eventsController      = [[UDEventsController alloc] init];
    self.variablesController   = [[UDVariablesController alloc] init];
    self.outlinePaneController = [[UDOutlinePaneController alloc] init];

    self.inspectorController.context   = self;
    self.eventsController.context      = self;
    self.variablesController.context   = self;
    self.outlinePaneController.context = self;
}

- (void)embedView:(NSView *)subview inContainer:(NSView *)container {
    if (!subview || !container) { return; }
    subview.frame = container.bounds;
    subview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:subview];
}

- (void)embedCollaboratorViews {
    [self embedView:self.outlinePaneController.view inContainer:self.sidebarContainerView];
    [self embedView:self.inspectorController.identityView inContainer:self.identityPanelView];
    [self embedView:self.inspectorController.view inContainer:self.attributesPanelView];
    [self embedView:self.inspectorController.sizeView inContainer:self.sizePanelView];
    [self embedView:self.variablesController.view inContainer:self.variablesPanelView];
    [self embedView:self.eventsController.view inContainer:self.eventsPanelView];
}

// MARK: - Window delegate

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self updateInspectorSectionLayout];
}

// MARK: - Inspector section layout

- (NSRect)frameForInspectorSection:(UDGuiInspectorSection)section {
    NSView *containerView = self.inspectorSectionTabView.superview;
    if (!containerView) { return NSZeroRect; }

    CGFloat availableWidth  = NSWidth(containerView.bounds);
    CGFloat availableHeight = NSMinY(self.inspectorSectionTabs.frame);
    if (availableHeight <= 0.0) {
        availableHeight = NSHeight(containerView.bounds);
    }

    if (section == UDGuiInspectorSectionAttributes || section == UDGuiInspectorSectionEvents) {
        return NSMakeRect(0.0, 0.0, availableWidth, availableHeight);
    }

    CGFloat compactHeight = 168.0;
    return NSMakeRect(0.0, MAX(0.0, availableHeight - compactHeight), availableWidth, compactHeight);
}

- (void)updateInspectorSectionLayout {
    if (!self.inspectorSectionTabView || !self.inspectorSectionTabs) { return; }

    NSRect sectionFrame = [self frameForInspectorSection:self.activeInspectorSection];
    if (NSEqualRects(sectionFrame, NSZeroRect)) { return; }

    self.inspectorSectionTabView.frame = sectionFrame;

    CGFloat compactHeight = 168.0;
    CGFloat fullHeight    = NSHeight(sectionFrame);
    CGFloat panelWidth    = NSWidth(sectionFrame);

    self.identityPanelView.frame   = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.attributesPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, fullHeight);
    self.sizePanelView.frame       = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.variablesPanelView.frame  = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.eventsPanelView.frame     = NSMakeRect(0.0, 0.0, panelWidth, fullHeight);
}

// MARK: - Refresh

- (void)refreshFromDocument {
    [self.outlinePaneController refreshOutlinePane];
    [self refreshDetailPaneForSelectedWindow];

    NSUInteger rootCount = self.ownerDocument.viewModel.rootWindows.count;
    if (self.statusLabel) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu root window%@",
                                       (unsigned long)rootCount, rootCount == 1 ? @"" : @"s"];
    }
    self.window.title = self.ownerDocument.displayName ?: @"GuiEd";
}

- (void)refreshDetailPaneForSelectedWindow {
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;

    if (self.breadcrumbLabel) {
        self.breadcrumbLabel.stringValue = self.ownerDocument.viewModel.selectedWindowBreadcrumb ?: @"";
    }

    [self updateInspectorPresentationForWindow:selectedWindow];
}

- (void)updateInspectorPresentationForWindow:(nullable UDGuiWindowNode *)selectedWindow {
    BOOL hasWindow      = selectedWindow != nil;
    BOOL identitySection= self.activeInspectorSection == UDGuiInspectorSectionIdentity;

    self.inspectorController.classNameField.enabled  = identitySection && hasWindow;
    self.inspectorController.windowNameField.enabled = identitySection && hasWindow;

    if (!hasWindow) {
        [self.inspectorController.classNameField selectItemAtIndex:-1];
        self.inspectorController.windowNameField.stringValue = @"";
    } else {
        [self.inspectorController.classNameField selectItemWithTitle:selectedWindow.className ?: @""];
        self.inspectorController.windowNameField.stringValue = selectedWindow.name ?: @"";
    }

    if (self.inspectorSectionTabView) {
        NSInteger sectionIndex = (NSInteger)self.activeInspectorSection;
        if (sectionIndex >= 0 && sectionIndex < (NSInteger)self.inspectorSectionTabView.numberOfTabViewItems) {
            [self.inspectorSectionTabView selectTabViewItemAtIndex:sectionIndex];
        }
    }
    [self updateInspectorSectionLayout];

    // Delegate panel sync to collaborators
    [self.inspectorController updateAttributeGroupVisibilityForWindow:selectedWindow];
    [self.inspectorController syncFromWindow:selectedWindow];
    [self.inspectorController refreshValidationHintsForWindow:selectedWindow];

    [self.variablesController reloadForWindow:selectedWindow
                             preserveSelection:YES
                                     selectRow:NSNotFound
                                  beginEditing:NO];
    [self.eventsController reloadForWindow:selectedWindow preserveSelection:YES];
}

// MARK: - Actions

- (IBAction)changeInspectorSection:(id)sender {
    (void)sender;
    self.activeInspectorSection = (UDGuiInspectorSection)self.inspectorSectionTabs.selectedSegment;
    [self refreshFromDocument];
}

- (void)beginEditingSelectedWindowIdentity:(id)sender {
    (void)sender;
    if (!self.ownerDocument.viewModel.selectedWindow) { return; }
    self.activeInspectorSection = UDGuiInspectorSectionIdentity;
    [self refreshFromDocument];
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.window makeFirstResponder:self.inspectorController.windowNameField];
        [self.inspectorController.windowNameField selectText:nil];
    }];
}

@end