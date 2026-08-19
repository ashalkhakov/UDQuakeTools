#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "UDBaseDocument.h"
#import "UDDeclManagedObjects.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * NSDocument subclass for a single decl, backed by its own decl editing
 * context (UDDeclIncrementalStore over idDeclManager, on the workspace's
 * shared store coordinator).
 *
 * Every decl document has a PRIVATE managed object context — the VSCode
 * model of one dirty buffer per open document. Many decls can be modified
 * at the same time; saving this document saves only ITS context, which
 * pushes just this document's changes (attribute edits, renames, file
 * moves, added/removed child decls) down into idDeclManager and rewrites
 * the affected decl files. Unsaved edits in other documents are untouched.
 *
 * Decl types that don't have a Core Data entity in DeclModel yet (anything
 * other than material/table/skin/particle/pda/email/audio/video today) fall
 * back to editing the idDecl's raw text directly against the manager;
 * declObject is nil for them.
 */
@interface UDDeclDocument : UDBaseDocument

- (nullable instancetype)initWithType:(declType_t)type name:(NSString *)name inWorkspace:(UDWorkspace *)workspace error:(NSError **)error;

/** The decl type this document was opened for. */
@property (nonatomic, readonly) declType_t declType;

/** The managed decl entity being edited (UDDeclPDA for pda decls, etc.), or
    nil when the decl type has no entity and the legacy text path is in use. */
@property (nonatomic, strong, readonly, nullable) __kindof UDDeclBase *declObject;

/** This document's private decl editing context (nil in legacy mode). */
@property (nonatomic, strong, readonly, nullable) NSManagedObjectContext *editingContext;

/**
 * "Save As": persists the buffer's CURRENT content as a brand-new decl named
 * newName (same type, same source file as the original), while the original
 * decl reverts to its last saved state — i.e. the unsaved edits transfer to
 * the new decl, exactly like Save As on a file buffer in VSCode. Returns the
 * newly created (and already saved) decl object, or nil on failure.
 *
 * Only entity-backed documents support this; the caller is expected to
 * re-open the editor on the returned decl. Child decl relationships (a PDA's
 * emails/audios/videos) stay with the original — the model's one-owner
 * inverse means they cannot be shared by two PDAs in the object graph.
 */
- (nullable __kindof UDDeclBase *)saveAsNewDeclNamed:(NSString *)newName error:(NSError **)error;

/** The raw decl source text, decoded from the decl object's sourceText. */
@property (nonatomic, copy, nullable) NSString *textContent;

/** Wire the document's text storage into the given NSTextView. */
- (void)setTextView:(NSTextView *)textView;

@end

NS_ASSUME_NONNULL_END
