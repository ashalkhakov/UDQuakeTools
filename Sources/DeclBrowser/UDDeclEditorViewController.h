#import "UDBaseEditorViewController.h"
#import <CoreData/CoreData.h>
#import <UDCodeKit/UDDiagnosticStore.h>

@class UDDeclDocument, UDDeclBase;

NS_ASSUME_NONNULL_BEGIN

/**
 * A structured editor of one decl (the PDA, table and skin editors): its
 * document, over the decl's managed object in an editing context of its own;
 * an object controller (from the subclass's XIB) whose content is the decl;
 * and a diagnostic store the Issues tab lists.
 */
@interface UDDeclEditorViewController : UDBaseEditorViewController

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

/// The line of the decl's text (1-based) where @a text first is, case
/// ignored; 1 when it is not there. Where a diagnostic about it points.
- (NSInteger)lineOfDeclTextContaining:(NSString *)text;

/// For the subclass: the decl has been opened (the object controller has
/// it); and the editing context changed (an edit, an undo).
- (void)declDidLoad;
- (void)editingContextDidChange;

@end

NS_ASSUME_NONNULL_END
