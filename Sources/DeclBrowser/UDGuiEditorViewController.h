#import "UDTextEditorViewController.h"
#import "UDBaseEditorViewController.h"

@class UDGuiPlayer, UDGuiView;

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
@interface UDGuiEditorViewController : UDTextEditorViewController <UDSourceRepresenting, UDInspecting>

@property (nonatomic, strong, readonly) UDGuiPlayer *player;

@property (strong) IBOutlet NSView *viewerView;
@property (weak) IBOutlet UDGuiView *guiView;
@property (weak) IBOutlet NSButton *playButton;
@property (weak) IBOutlet NSTextField *timeLabel;
@property (weak) IBOutlet NSPopUpButton *namedEventPopUp;
/// The inspector's panes: the state, and the log.
@property (strong) IBOutlet NSView *stateView;
@property (strong) IBOutlet NSView *logView;
@property (weak) IBOutlet NSTableView *stateTable;
@property (weak) IBOutlet NSTableView *logTable;

- (IBAction)togglePlaying:(nullable id)sender;
- (IBAction)step:(nullable id)sender;
- (IBAction)restart:(nullable id)sender;
/// A menu item's title, sent as a named event.
- (IBAction)sendNamedEvent:(nullable id)sender;
/// The + and − under the state: a new key, or the selected one taken off.
- (IBAction)addOrRemoveStateKey:(nullable id)sender;
- (IBAction)clearLog:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
