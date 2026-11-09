/*---------------------------------------------------------------------------------------------
 *  UQExtension.h
 *
 *  UDCode's UDQuakeTools extension (docs/UDCODE.md): Quarry and Pak Manager
 *  in UDCode's windows. Active in a folder with a .qworkspace (its
 *  LanguageInfo.plist's workspaceContains:), where the window's project is
 *  a Quarry project (UQProject): the Decls navigator, the quarry: URLs of
 *  its decls and game files. The idScript and idDecl grammars are its own,
 *  in every window, and udscript-lsp is idScript's language server.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>

@class UQProject;

NS_ASSUME_NONNULL_BEGIN

@interface UQExtension : NSObject <UDExtension>

/// The Quarry project of @a workbench's window, made the first time it is
/// asked for; nil: the window has no folder.
- (nullable UQProject *)projectOfWorkbench:(id<UDWorkbench>)workbench;

@end

NS_ASSUME_NONNULL_END
