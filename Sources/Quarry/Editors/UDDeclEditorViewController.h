#import "UDBaseEditorViewController.h"
#import <CoreData/CoreData.h>
#import <UDCodeKit/UDDiagnosticStore.h>

@class UDDeclDocument, UDDeclBase, UDReferencePicker;

/// What a field's picker chooses from.
typedef NS_ENUM(NSInteger, UDReferenceKind) {
    UDReferenceDecls,       // the decls of a type
    UDReferenceMaterials,   // material decls, and images (what a material may be)
    UDReferenceImages,      // image files, with their extensions
    UDReferenceModels,      // model files
    UDReferenceVideos,      // cinematics (.roq)
    UDReferenceGuis,        // GUI files
    UDReferenceNames,       // names the editor gives (joints, bodies, actions)
};

/// A field that names something, and its picker (the "…" beside it).
@interface UDReferenceField : NSObject
+ (instancetype)fieldTitled:(NSString *)title key:(NSString *)key controller:(id)controller kind:(UDReferenceKind)kind;
@property (nonatomic, copy) NSString *title;
/// The value set: selection.<key> of the controller (an object or array
/// controller), as the field's binding sets it.
@property (nonatomic, copy) NSString *key;
@property (nonatomic, weak) id controller;
@property (nonatomic) UDReferenceKind kind;
/// For UDReferenceDecls: the decls' type (a declType_t).
@property (nonatomic) int declType;
/// For UDReferenceNames: the names, and what each is.
@property (nonatomic, copy, nullable) NSArray<NSString *> *names;
@property (nonatomic, copy, nullable) NSArray<NSString *> *details;
@end

NS_ASSUME_NONNULL_BEGIN

/**
 * A structured editor of one decl (the PDA, table and skin editors): its
 * document, over the decl's managed object in an editing context of its own;
 * an object controller (from the subclass's XIB) whose content is the decl;
 * and a diagnostic store the Issues tab lists.
 */
@interface UDDeclEditorViewController : UDBaseEditorViewController <UDSourceRepresenting>

/** The backing NSDocument (undo, save, dirty). Made as the view loads. */
@property (nonatomic, strong, nullable) UDDeclDocument *document;

/** The decl being edited, in the document's editing context. */
@property (nonatomic, readonly, nullable) __kindof UDDeclBase *declObject;
@property (nonatomic, readonly, nullable) NSManagedObjectContext *editingContext;

@property (strong) IBOutlet NSObjectController *objectController;

/// What is wrong with the decl, as the Issues tab lists it; the subclass
/// fills it (-editingContextDidChange).
@property (nonatomic, strong, readonly, nullable) UDDiagnosticStore *diagnosticStore;

/// Shows what @a diagnostic is about. Nothing by default.
- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic;

/// What a diagnostic is about, for -revealDiagnostic:, by what it says (its
/// line and message): the store's items are new ones each time the decl is
/// checked again, the same as the last.
- (void)setTarget:(id)target forDiagnostic:(UDDiagnosticItem *)diagnostic;
- (nullable id)targetForDiagnostic:(UDDiagnosticItem *)diagnostic;
- (void)removeDiagnosticTargets;

/// Before a list's row @a row is taken off, the selection moved off it: to
/// the row before, or to none. (GNUstep's array controller reads a selection
/// past the end of its new content, and raises.)
- (void)moveSelectionOffRow:(NSUInteger)row inController:(NSArrayController *)controller;

/// After a list's row @a row is taken off, its neighbour selected, as
/// DialogParticleEditor's RemoveStage selects it (the one before, or the
/// one after the first); nothing in an empty list. (GNUstep's array
/// controller keeps a selection past the end otherwise.)
- (void)selectRowAfterRemovingRow:(NSUInteger)row inController:(NSArrayController *)controller;

/// A material the engine finds: a decl, one of its own ("_default"), or an
/// image of that name, which it makes a material of. (A skin's, a particle
/// stage's.)
- (BOOL)materialExists:(NSString *)name;

/// The picker of the field whose "…" has tag @a tag (subclasses say);
/// nil for none.
- (nullable UDReferenceField *)referenceFieldForTag:(NSInteger)tag;
/// A "…" clicked: its field's picker, as a sheet; the name chosen set as
/// the field's value (one edit).
- (IBAction)pickReference:(nullable id)sender;
/// What a picker offers: names, and what each is in @a details.
- (NSArray<NSString *> *)namesFor:(UDReferenceField *)field details:(NSMutableArray<NSString *> *)details;
/// The picker up, if one is.
@property (nonatomic, strong, readonly, nullable) UDReferencePicker *referencePicker;

/// The line of the decl's text (1-based) where @a text first is, case
/// ignored; 1 when it is not there. Where a diagnostic about it points.
- (NSInteger)lineOfDeclTextContaining:(NSString *)text;

/// The decl's source in place of the editor: its text as it would be saved
/// now, in the code editor, highlighted as a decl. Back in the editor, the
/// text, if edited, is read into the decl as one edit (undone as one); text
/// that does not parse keeps the source up, the parser's error shown. Both
/// share the document, its undo and its dirty state; saving in the source
/// saves the text.
@property (nonatomic) BOOL showsSource;

/// The source's text view while the source is up, else nil.
@property (nonatomic, readonly, nullable) NSTextView *sourceTextView;

/// For the subclass: the decl has been opened (the object controller has
/// it); and the editing context changed (an edit, an undo).
- (void)declDidLoad;
- (void)editingContextDidChange;

@end

NS_ASSUME_NONNULL_END
