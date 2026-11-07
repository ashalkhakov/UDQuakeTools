/*---------------------------------------------------------------------------------------------
 *  UQExtension.m
 *--------------------------------------------------------------------------------------------*/

#import "UQExtension.h"
#import "UQProject.h"
#import "UQDeclDocument.h"
#import "UQEditorHost.h"
#import "UQGuiDocument.h"
#import "UQPakDocument.h"
#import "UDArchiveBrowserController.h"
#import "UQCommands.h"
#import "UDGuiEditorViewController.h"
#import "UDBaseEditorViewController.h"
#import "UDDeclEditorViewController.h"

typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_idscript(void);
const TSLanguage *tree_sitter_iddecl(void);

@implementation UQExtension {
    NSBundle *_bundle;
    NSMapTable<id<UDWorkbench>, UQProject *> *_projects;
    NSMapTable<id<UDWorkbench>, UQCommands *> *_commands;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    _projects = [NSMapTable weakToStrongObjectsMapTable];
    _commands = [NSMapTable weakToStrongObjectsMapTable];
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    _projects = nil;
}

- (const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"idscript"]) return tree_sitter_idscript;
    if ([identifier isEqualToString:@"iddecl"]) return tree_sitter_iddecl;
    return NULL;
}

/// udscript-lsp, beside the bundle's binary ($UD_SCRIPT_LSP, a test's): it
/// reads the game from the project's .qworkspace (initialize's rootUri).
- (NSArray<NSString *> *)languageServerCommandForIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:@"idscript"]) return nil;
    NSString *tool = NSProcessInfo.processInfo.environment[@"UD_SCRIPT_LSP"]
        ?: [_bundle pathForAuxiliaryExecutable:@"udscript-lsp"];
    return tool ? @[ tool ] : nil;
}

// ---------------------------------------------------------------------------
// MARK: - The window's project
// ---------------------------------------------------------------------------

- (UQProject *)projectOfWorkbench:(id<UDWorkbench>)workbench {
    UQProject *project = [_projects objectForKey:workbench];
    NSURL *folder = workbench.project.folderURL;
    if (project || !folder) return project;
    // a Quarry project: a folder with a .qworkspace (the extension is active
    // everywhere, for Pak Manager's paks)
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder.path error:NULL];
    if (![[names valueForKey:@"pathExtension"] containsObject:@"qworkspace"]) return nil;
    project = [[UQProject alloc] initWithFolder:folder workbench:workbench];
    [_projects setObject:project forKey:workbench];
    return project;
}

/// The Decls navigator: the project's decls, scripts and GUIs.
- (NSViewController *)navigatorViewControllerForWorkbench:(id<UDWorkbench>)workbench {
    UQProject *project = [self projectOfWorkbench:workbench];
    if (!project) return nil;
    UDTreeViewController *tree = [[UDTreeViewController alloc] initWithDataProvider:project workbench:workbench title:@"Decls"];
    project.treeView = tree;
    return tree;
}

/// The project's commands (UQEditorMenus.xib): New Declaration…, Test
/// Declaration, the GUI editor's; none in a window that is no Quarry project.
- (NSArray<NSMenuItem *> *)editorMenuItemsForWorkbench:(id<UDWorkbench>)workbench {
    UQProject *project = [self projectOfWorkbench:workbench];
    if (!project) return @[];
    UQCommands *commands = [_commands objectForKey:workbench];
    if (!commands) {
        commands = [[UQCommands alloc] initWithProject:project];
        [_commands setObject:commands forKey:workbench];
    }
    return commands.menuItems;
}

- (id<UDFileSystemProvider>)workbench:(id<UDWorkbench>)workbench fileSystemProviderForScheme:(NSString *)scheme {
    return [scheme isEqualToString:@"quarry"] ? [self projectOfWorkbench:workbench] : nil;
}

// ---------------------------------------------------------------------------
// MARK: - Documents and their editors
// ---------------------------------------------------------------------------

/// A decl with a structured editor: Quarry's document of it, its Core Data
/// objects the model (a custom document); any other quarry: URL is text.
- (id<UDCustomDocument>)workbench:(id<UDWorkbench>)workbench openCustomDocumentAtURL:(NSURL *)url
               fileSystemProvider:(id<UDFileSystemProvider>)provider error:(NSError **)error {
    // a pak, Pak Manager's, wherever it is
    if ([UQPakDocument isPakURL:url]) return [[UQPakDocument alloc] initWithURL:url error:error];
    NSString *typeName, *name, *path;
    if (![UQProject parseURL:url typeName:&typeName name:&name path:&path]) return nil;
    UDWorkspace *workspace = [self projectOfWorkbench:workbench].workspace;
    if (!workspace) return nil;
    // a GUI: its source and canvas, Quarry's GUI editor's
    if (path) {
        return [UQGuiDocument isGuiPath:path] ? [[UQGuiDocument alloc] initWithPath:path inWorkspace:workspace error:error] : nil;
    }
    if (![UQDeclDocument isStructuredDeclType:typeName inWorkspace:workspace]) return nil;
    return [[UQDeclDocument alloc] initWithDeclType:typeName name:name inWorkspace:workspace error:error];
}

- (NSViewController *)workbench:(id<UDWorkbench>)workbench editorForDocument:(UDCodeDocument *)document {
    if ([document.customDocument isKindOfClass:[UQPakDocument class]]) {
        return [[UDArchiveBrowserController alloc] initWithDocument:[(UQPakDocument *)document.customDocument archiveDocument]];
    }
    if ([document.customDocument isKindOfClass:[UQGuiDocument class]]) {
        UQGuiDocument *gui = (UQGuiDocument *)document.customDocument;
        UDGuiEditorViewController *editor = [[UDGuiEditorViewController alloc] init];
        editor.item = gui.item;
        editor.workspace = gui.workspace;
        editor.document = gui.textDocument;
        gui.editor = editor;
        return [[UQEditorHost alloc] initWithEditor:editor document:document workbench:workbench];
    }
    if (![document.customDocument isKindOfClass:[UQDeclDocument class]]) return nil;
    UQDeclDocument *decl = (UQDeclDocument *)document.customDocument;
    UDBaseEditorViewController *editor = [UDBaseEditorViewController editorViewControllerForWorkspaceItem:decl.item
                                                                                             inWorkspace:decl.workspace];
    if (![editor isKindOfClass:[UDDeclEditorViewController class]]) return nil;
    // the custom document's model, the one its editor edits
    [(UDDeclEditorViewController *)editor setDocument:decl.declDocument];
    return [[UQEditorHost alloc] initWithEditor:editor document:document workbench:workbench];
}

@end
