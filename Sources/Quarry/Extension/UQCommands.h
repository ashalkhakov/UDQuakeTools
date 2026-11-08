/*---------------------------------------------------------------------------------------------
 *  UQCommands.h
 *
 *  A Quarry project's commands, in UDCode's Editor menu (-[UDExtension
 *  editorMenuItemsForWorkbench:], from UQEditorMenus.xib, this the XIB's
 *  owner): Find in Decls… (Quarry's Find, in the bottom area), New
 *  Declaration…, New PDA…, New Skin… (a decl made through the
 *  game's decl store, opened in its tab), and Test Declaration (the front
 *  decl's text checked as the engine reads it, its problems the document's
 *  issues). The GUI editor's own items (zoom, the grid, the status bar)
 *  have no target: they go to the front tab's editor.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>

@class UQProject;

NS_ASSUME_NONNULL_BEGIN

@interface UQCommands : NSObject

/// @a extension's (its segment in the bottom area, Find's).
- (instancetype)initWithProject:(UQProject *)project extension:(nullable id<UDExtension>)extension;

@property (nonatomic, weak, readonly) UQProject *project;
/// The menu's items (UQEditorMenus.xib's), their target this.
@property (nonatomic, readonly, copy) NSArray<NSMenuItem *> *menuItems;
@property (nonatomic, strong, nullable) IBOutlet NSMenu *menu;

/// A decl of @a typeName named @a name in @a fileName (nil: where the store
/// puts one of its type), made and saved; NO and why.
- (BOOL)createDeclOfTypeName:(NSString *)typeName named:(NSString *)name fileName:(nullable NSString *)fileName
                       error:(NSError *_Nullable *_Nullable)error;

/// @a document's text (a decl's) checked as the engine reads it: its
/// problems, which -testDecl: makes the document's issues.
- (NSArray<UDDiagnosticItem *> *)problemsOfDeclDocument:(UDCodeDocument *)document;

- (IBAction)newDecl:(nullable id)sender;
- (IBAction)newPDA:(nullable id)sender;
- (IBAction)newSkin:(nullable id)sender;
- (IBAction)testDecl:(nullable id)sender;
/// Quarry's Find in the bottom area, under the extension's segment.
- (IBAction)findInDecls:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
