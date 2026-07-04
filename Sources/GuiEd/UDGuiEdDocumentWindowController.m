/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController.h"
#import "UDGuiEdDocumentWindowController+Events.h"
#import "UDGuiEdDocumentWindowController+EventsTable.h"
#import "UDGuiEdDocumentWindowController+OutlinePane.h"
#import "UDGuiEdDocumentWindowController+TableSelection.h"
#import "UDGuiEdDocumentWindowController+TypedPanels.h"
#import "UDGuiEdDocumentWindowController+DetailPane.h"
#import "UDGuiEdDocumentWindowController+Variables.h"
#import "UDGuiEdDocumentWindowController+VariablesTable.h"
#import "UDGuiEdDocument.h"
#import "UDInspectableTableView.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"
typedef NS_ENUM(NSInteger, UDGuiInspectorSection) {
    UDGuiInspectorSectionIdentity = 0,
    UDGuiInspectorSectionAttributes,
    UDGuiInspectorSectionSize,
    UDGuiInspectorSectionVariables,
    UDGuiInspectorSectionEvents,
};

static NSPasteboardType const UDGuiEventsReorderPasteboardType = @"com.udquake.guied.reorder-row";

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
@property (nonatomic, assign) UDGuiInspectorSection activeInspectorSection;
@property (nonatomic, strong) NSTableView *eventHandlersTableView;
@property (nonatomic, strong) NSTableView *eventCommandsTableView;
@property (nonatomic, strong) IBOutlet NSPopUpButton *eventCommandTypePopup;
@property (nonatomic, strong) IBOutlet NSTabView *eventCommandEditorTabView;
@property (nonatomic, strong) IBOutlet NSTextField *eventSetVariableField;
@property (nonatomic, strong) IBOutlet NSTextField *eventSetValueField;
@property (nonatomic, strong) IBOutlet NSTextField *eventSetFocusWindowField;
@property (nonatomic, strong) IBOutlet NSTextField *eventResetTimeWindowField;
@property (nonatomic, strong) IBOutlet NSTextField *eventResetTimeValueField;
@property (nonatomic, strong) IBOutlet NSTextField *eventTransitionVariableField;
@property (nonatomic, strong) IBOutlet NSTextField *eventTransitionFromField;
@property (nonatomic, strong) IBOutlet NSTextField *eventTransitionToField;
@property (nonatomic, strong) IBOutlet NSTextField *eventTransitionTimeField;
@property (nonatomic, strong) IBOutlet NSTextField *eventTransitionAccelField;
@property (nonatomic, strong) IBOutlet NSTextField *eventTransitionDecelField;
@property (nonatomic, strong) IBOutlet NSTextField *eventLocalSoundField;
@property (nonatomic, strong) IBOutlet NSTextField *eventRunScriptField;
@property (nonatomic, strong) IBOutlet NSTextField *eventShowCursorField;
@property (nonatomic, strong) IBOutlet NSTextField *eventFallbackArgumentsField;
@property (nonatomic, assign) BOOL suppressEventCommandEditorCommit;
@end

@implementation UDGuiEdDocumentWindowController

- (NSRect)frameForInspectorSection:(UDGuiInspectorSection)section {
    NSView *containerView = self.inspectorSectionTabView.superview;
    if (!containerView) {
        return NSZeroRect;
    }

    CGFloat availableWidth = NSWidth(containerView.bounds);
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
    if (!self.inspectorSectionTabView || !self.inspectorSectionTabs) {
        return;
    }

    NSRect sectionFrame = [self frameForInspectorSection:self.activeInspectorSection];
    if (NSEqualRects(sectionFrame, NSZeroRect)) {
        return;
    }

    self.inspectorSectionTabView.frame = sectionFrame;

    CGFloat compactHeight = 168.0;
    CGFloat fullHeight = NSHeight(sectionFrame);
    CGFloat panelWidth = NSWidth(sectionFrame);

    self.identityPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.attributesPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, fullHeight);
    self.sizePanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.variablesPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.eventsPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, fullHeight);
}

- (instancetype)initWithDocument:(UDGuiEdDocument *)document {
    self = [super initWithWindowNibName:@"UDGuiEdDocument"];
    if (!self) {
        return nil;
    }

    _ownerDocument = document;
    _activeInspectorSection = UDGuiInspectorSectionAttributes;
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.delegate = (id<NSWindowDelegate>)self;
    if (self.inspectorSectionTabs) {
        [self.inspectorSectionTabs setSelectedSegment:(NSInteger)self.activeInspectorSection];
        [self.inspectorSectionTabs setToolTip:@"Identity & Type" forSegment:0];
        [self.inspectorSectionTabs setToolTip:@"Attributes" forSegment:1];
        [self.inspectorSectionTabs setToolTip:@"Size" forSegment:2];
        [self.inspectorSectionTabs setToolTip:@"Variables" forSegment:3];
        [self.inspectorSectionTabs setToolTip:@"Events" forSegment:4];
    }

    if (self.eventHandlersTableView) {
        [self.eventHandlersTableView registerForDraggedTypes:@[UDGuiEventsReorderPasteboardType]];
        [self.eventHandlersTableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    }
    if (self.eventCommandsTableView) {
        [self.eventCommandsTableView registerForDraggedTypes:@[UDGuiEventsReorderPasteboardType]];
        [self.eventCommandsTableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    }

    [self refreshFromDocument];
    [self scrollAttributesPanelToTop];
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self updateInspectorSectionLayout];
}

- (void)scrollAttributesPanelToTop {
    if (!self.attributesScrollView) {
        return;
    }
    NSView *docView = self.attributesScrollView.documentView;
    if (!docView) {
        return;
    }
    CGFloat maxY = NSMaxY(docView.bounds) - NSHeight(self.attributesScrollView.contentView.bounds);
    [self.attributesScrollView.contentView scrollToPoint:NSMakePoint(0.0, MAX(0.0, maxY))];
    [self.attributesScrollView reflectScrolledClipView:self.attributesScrollView.contentView];
}

- (IBAction)changeInspectorSection:(id)sender {
    (void)sender;
    self.activeInspectorSection = (UDGuiInspectorSection)self.inspectorSectionTabs.selectedSegment;
    [self refreshFromDocument];
    [self scrollAttributesPanelToTop];
}

- (void)refreshFromDocument {
    [self refreshOutlinePane];
    [self refreshDetailPaneForSelectedWindow];

    NSUInteger rootCount = self.ownerDocument.viewModel.rootWindows.count;
    if (self.statusLabel) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu root window%@", (unsigned long)rootCount, rootCount == 1 ? @"" : @"s"];
    }
    self.window.title = self.ownerDocument.displayName ?: @"GuiEd";
}

- (void)updateInspectorPresentationForWindow:(UDGuiWindowNode *)selectedWindow {
    BOOL hasWindow = selectedWindow != nil;
    BOOL identitySection = self.activeInspectorSection == UDGuiInspectorSectionIdentity;

    self.classNameField.enabled = identitySection && hasWindow;
    self.windowNameField.enabled = identitySection && hasWindow;

    if (self.inspectorSectionTabView) {
        NSInteger sectionIndex = (NSInteger)self.activeInspectorSection;
        if (sectionIndex >= 0 && sectionIndex < (NSInteger)self.inspectorSectionTabView.numberOfTabViewItems) {
            [self.inspectorSectionTabView selectTabViewItemAtIndex:sectionIndex];
        }
    }

    [self updateInspectorSectionLayout];

    [self updateAttributeGroupVisibilityForWindow:selectedWindow];

    [self syncCommonInfoPanelFromWindow:selectedWindow];
    [self syncTypedPanelsFromWindow:selectedWindow];
    [self refreshTypedValidationHintsForWindow:selectedWindow];

    if (self.activeInspectorSection == UDGuiInspectorSectionAttributes) {
        self.statusLabel.stringValue = selectedWindow ? @"Common and typed attribute editor active. Generic properties are shown first." : self.statusLabel.stringValue;
    }

    if (!hasWindow) {
        self.classNameField.stringValue = @"";
        self.windowNameField.stringValue = @"";
    }
}

- (IBAction)commitTypedAttributesPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) {
        return;
    }

    if (![self validateTypedPanelsForWindow:window]) {
        [self refreshTypedValidationHintsForWindow:window];
        return;
    }

    [self applyTypedPanelsToWindow:window];

    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

- (IBAction)commitWindowInfoPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) {
        return;
    }

    [self applyCommonInfoPanelToWindow:window];

    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

- (IBAction)commitTypedSizePanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) {
        return;
    }

    if (![self validateSizePanelForWindow:window]) {
        [self refreshTypedValidationHintsForWindow:window];
        return;
    }

    [self applySizePanelToWindow:window];
    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshTypedValidationHintsForWindow:self.ownerDocument.viewModel.selectedWindow];
    [self refreshFromDocument];
}

- (IBAction)commitTypedVariablesPanel:(id)sender {
    (void)sender;
}

- (IBAction)commitTypedEventsPanel:(id)sender {
    (void)sender;
    // Events are committed through the handlers/commands table editor actions.
}
#pragma mark - Table view data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.variablesTableView) {
        return (NSInteger)[self selectedWindowVariableDefinitions].count;
    }
    if (tableView == self.eventHandlersTableView) {
        return (NSInteger)[self selectedWindowEventHandlers].count;
    }
    if (tableView == self.eventCommandsTableView) {
        return (NSInteger)[self selectedEventHandler].commands.count;
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.variablesTableView) {
        return [self tableViewObjectValueForVariablesTableView:tableView column:tableColumn row:row];
    }
    return [self tableViewObjectValueForEventsTableView:tableView column:tableColumn row:row];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.variablesTableView) {
        [self tableViewSetObjectValueForVariablesTableView:tableView object:object column:tableColumn row:row];
    } else {
        [self tableViewSetObjectValueForEventsTableView:tableView object:object column:tableColumn row:row];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self handleTableViewSelectionDidChangeNotification:notification];
}

@end