#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "UDBaseDocument.h"
#import "UDDeclManagedObjects.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * NSDocument subclass for a single decl, backed by the workspace's decl
 * editing context (UDDeclIncrementalStore over idDeclManager).
 *
 * The document pulls a managed decl entity out of the incremental store;
 * editors either bind to its structured attributes (e.g. the PDA editor) or
 * edit its raw sourceText through a text view. Saving the document saves the
 * shared managed object context, which pushes all changes (attribute edits,
 * renames, file moves, added/removed child decls) down into idDeclManager
 * and writes the decl files out.
 *
 * Decl types that don't have a Core Data entity in DeclModel yet (anything
 * other than material/pda/email/audio/video today) fall back to editing the
 * idDecl's raw text directly against the manager; declObject is nil for them.
 */
@interface UDDeclDocument : UDBaseDocument

- (nullable instancetype)initWithType:(declType_t)type name:(NSString *)name inWorkspace:(UDWorkspace *)workspace error:(NSError **)error;

/** The managed decl entity being edited (UDDeclPDA for pda decls, etc.), or
    nil when the decl type has no entity and the legacy text path is in use. */
@property (nonatomic, strong, readonly, nullable) __kindof UDDeclBase *declObject;

/** The shared decl editing context declObject lives in (nil in legacy mode). */
@property (nonatomic, strong, readonly, nullable) NSManagedObjectContext *editingContext;

/** The raw decl source text, decoded from the decl object's sourceText. */
@property (nonatomic, copy, nullable) NSString *textContent;

/** Wire the document's text storage into the given NSTextView. */
- (void)setTextView:(NSTextView *)textView;

@end

NS_ASSUME_NONNULL_END
