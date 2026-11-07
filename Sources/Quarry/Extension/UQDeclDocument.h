/*---------------------------------------------------------------------------------------------
 *  UQDeclDocument.h
 *
 *  A decl with a structured editor (a material, a particle, a PDA…), in
 *  UDCode as a custom document (UDCodeKit's UDCustomDocument, VS Code's
 *  CustomDocument): its model Quarry's own, a UDDeclDocument, Core Data
 *  objects in a context of its own over the game's decl store, edited
 *  through its editor's bindings, undone by the context's undo manager,
 *  saved through the store and the decl manager into the savepath. Its text
 *  (Open as Text) is the decl's as it is now, unsaved edits and all; typed
 *  there, it goes back as one edit of the objects.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDCodeKit/UDCodeKit.h>

@class UDWorkspace, UDDeclDocument, UDDeclItem;

NS_ASSUME_NONNULL_BEGIN

@interface UQDeclDocument : NSObject <UDCustomDocument>

/// Whether decls of @a typeName are edited so (they have an entity in the
/// decl model and a structured editor); the others are text documents.
+ (BOOL)isStructuredDeclType:(NSString *)typeName inWorkspace:(UDWorkspace *)workspace;

/// The decl @a name of type @a typeName, read; nil and why when it can't be.
- (nullable instancetype)initWithDeclType:(NSString *)typeName name:(NSString *)name
                              inWorkspace:(UDWorkspace *)workspace error:(NSError *_Nullable *_Nullable)error;

@property (nonatomic, readonly) UDWorkspace *workspace;
/// Quarry's document of it, which its editor edits.
@property (nonatomic, readonly) UDDeclDocument *declDocument;
/// What its editor is made for (UDBaseEditorViewController's factory).
@property (nonatomic, readonly) UDDeclItem *item;

@end

NS_ASSUME_NONNULL_END
