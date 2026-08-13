#import "UDBaseEditorViewController.h"

@class idDeclEmail, idDeclVideo, idDeclAudio;
@class UDDeclDocument;

NS_ASSUME_NONNULL_BEGIN

@interface UDPDAEditorViewController : UDBaseEditorViewController

/** The backing NSDocument (handles undo/save/dirty). Created lazily in viewDidLoad. */
@property (nonatomic, strong, nullable) UDDeclDocument *document;

@property (strong) IBOutlet NSObjectController *objectController;
@property (strong) IBOutlet NSArrayController *audioArrayController;
@property (strong) IBOutlet NSArrayController *videoArrayController;
@property (strong) IBOutlet NSArrayController *emailArrayController;

- (IBAction)generateId:(NSSegmentedControl *)sender;
- (IBAction)addOrRemoveAudioLog:(NSSegmentedControl *)sender;
- (IBAction)addOrRemoveEmail:(NSSegmentedControl *)sender;
- (IBAction)addOrRemoveVideo:(NSSegmentedControl *)sender;
- (IBAction)audioLogEdit:(id)sender;
- (IBAction)emailEdit:(id)sender;
- (IBAction)videoEdit:(id)sender;

@end

@interface UDPDAAudioEditorViewController : NSObject

@property IBOutlet NSWindow *window;
@property (strong) IBOutlet NSObjectController *objectController;

@property idDeclAudio *editingAudio;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

@end

@interface UDPDAEmailEditorViewController : NSObject

@property IBOutlet NSWindow *window;
@property (strong) IBOutlet NSObjectController *objectController;

@property idDeclEmail *editingEmail;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

@end

@interface UDPDAVideoEditorViewController : NSObject

@property IBOutlet NSWindow *window;
@property (strong) IBOutlet NSObjectController *objectController;

@property idDeclVideo *editingVideo;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

@end

NS_ASSUME_NONNULL_END
