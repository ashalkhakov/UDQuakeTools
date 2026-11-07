/*---------------------------------------------------------------------------------------------
 *  UQGuiDocument.h
 *
 *  A GUI (guis/…/*.gui), in UDCode as a custom document (UDCodeKit's
 *  UDCustomDocument): its model Quarry's, a UDTextFileDocument the GUI
 *  editor edits — its source, and its canvas, whose edits are its text once
 *  saved (or shown) — undone by that document's undo manager, saved through
 *  the game's file system into the savepath. Its text (Open as Text) is the
 *  GUI's as it is now, the canvas's edits in it; typed there, it is one Edit
 *  Source of the GUI.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDCodeKit/UDCodeKit.h>

@class UDWorkspace, UDTextFileDocument, UDFileItem, UDGuiEditorViewController;

NS_ASSUME_NONNULL_BEGIN

@interface UQGuiDocument : NSObject <UDCustomDocument>

/// Whether @a path (the game's) is a GUI's.
+ (BOOL)isGuiPath:(NSString *)path;

/// The GUI at @a path in @a workspace's game, read; nil and why.
- (nullable instancetype)initWithPath:(NSString *)path inWorkspace:(UDWorkspace *)workspace
                                error:(NSError *_Nullable *_Nullable)error;

@property (nonatomic, readonly) UDWorkspace *workspace;
@property (nonatomic, readonly) UDTextFileDocument *textDocument;
@property (nonatomic, readonly) UDFileItem *item;
/// Its editor, once it has one: what its text is now.
@property (nonatomic, weak, nullable) UDGuiEditorViewController *editor;

@end

NS_ASSUME_NONNULL_END
