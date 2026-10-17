#import "UDTextEditorViewController.h"
#import "UDBaseEditorViewController.h"
#import "UDGuiView.h"

@class UDGuiPlayer, UDGuiView, rvGEWorkspace, UDTransportController;

NS_ASSUME_NONNULL_BEGIN

/**
 * A .gui file's tab: the GUI running (UDGuiPlayer, in a UDGuiView) as the
 * game would run it, with its clock and the named events its windows have;
 * in the inspector, the state the game would give it and a log of what it
 * asks of the game; and,
 * under Editor | Source, its text in the code editor (the text editor's,
 * whose document saves it). Back from the source, an edited text is run
 * instead, its parse errors in the tab's Issues.
 */
@interface UDGuiEditorViewController : UDTextEditorViewController <UDSourceRepresenting, UDInspecting, UDNavigating, UDGuiViewDesignDelegate>

@property (nonatomic, strong, readonly) UDGuiPlayer *player;

/// Run | Design: the GUI run, or designed (the GUI editor's workspace, its
/// canvas: select, move and size its windows, with Undo).
@property (nonatomic, readonly) BOOL designing;
/// The text the player was last read from: the file's, the source's, or
/// the design's (the design's edits since are made in the run as it is).
@property (nonatomic, copy, readonly, nullable) NSString *runningText;
@property (nonatomic, strong, readonly, nullable) rvGEWorkspace *designWorkspace;
@property (weak) IBOutlet NSSegmentedControl *modeControl;
- (IBAction)changeMode:(nullable id)sender;

@property (strong) IBOutlet NSView *viewerView;
@property (weak) IBOutlet UDGuiView *guiView;
/// The time controls, the other editors' (UDTransportController's bar,
/// in transportView): dragged, the GUI goes to it, running or designed;
/// Play only running.
@property (weak) IBOutlet NSView *transportView;
@property (nonatomic, strong, readonly) UDTransportController *transport;
@property (weak) IBOutlet NSPopUpButton *namedEventPopUp;
/// The navigator's pane: the GUI's windows (rvGENavigator's), a check box
/// hiding each in the design.
@property (strong) IBOutlet NSView *windowsView;
@property (weak) IBOutlet NSOutlineView *windowsOutline;
/// The inspector's Properties (rvGEProperties): the selected window's state
/// keys, edited as the window reads them, each a Property Change.
@property (strong) IBOutlet NSView *propertiesView;
@property (weak) IBOutlet NSTableView *propertiesTable;
@property (weak) IBOutlet NSTextField *propertiesMessage;
@property (weak) IBOutlet NSTextField *propertiesPlaceholder;
- (IBAction)addProperty:(nullable id)sender;

/// The design's menu (rvGEWorkspace's popup, IDR_GUIED_ITEM_POPUP): New,
/// Select (filled with the windows under the click), Arrange, Align, Make
/// Same Size, Copy, Paste, Delete, Scripts, Properties.
@property (strong) IBOutlet NSMenu *designMenu;
@property (weak) IBOutlet NSMenu *selectMenu;
- (IBAction)newWindow:(nullable id)sender;
- (IBAction)selectWindowFromMenu:(nullable id)sender;
- (IBAction)bringToFront:(nullable id)sender;
- (IBAction)bringForward:(nullable id)sender;
- (IBAction)sendToBack:(nullable id)sender;
- (IBAction)sendBackward:(nullable id)sender;
- (IBAction)makeChild:(nullable id)sender;
- (IBAction)alignWindows:(nullable id)sender;
- (IBAction)makeSameSize:(nullable id)sender;
- (IBAction)copyWindows:(nullable id)sender;
- (IBAction)pasteWindows:(nullable id)sender;
- (IBAction)deleteWindows:(nullable id)sender;
- (IBAction)showScripts:(nullable id)sender;
/// The inspector's Properties shown (a window double-clicked).
- (IBAction)showProperties:(nullable id)sender;
/// The inspector's Scripts (GEItemScriptsDlg): the selected window's
/// variables and scripts as text, applied as one Scripts Change.
@property (strong) IBOutlet NSView *scriptsView;
@property (weak) IBOutlet NSTextView *scriptsText;
@property (weak) IBOutlet NSTextField *scriptsMessage;
@property (weak) IBOutlet NSTextField *scriptsPlaceholder;
- (IBAction)applyScripts:(nullable id)sender;
- (IBAction)revertScripts:(nullable id)sender;
/// The inspector's panes: the state, and the log.
@property (strong) IBOutlet NSView *stateView;
@property (strong) IBOutlet NSView *logView;
@property (weak) IBOutlet NSTableView *stateTable;
@property (weak) IBOutlet NSTableView *logTable;

/// A menu item's title, sent as a named event.
- (IBAction)sendNamedEvent:(nullable id)sender;
/// The + and − under the state: a new key, or the selected one taken off.
- (IBAction)addOrRemoveStateKey:(nullable id)sender;
- (IBAction)clearLog:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
