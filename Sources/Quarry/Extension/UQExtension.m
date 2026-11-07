/*---------------------------------------------------------------------------------------------
 *  UQExtension.m
 *--------------------------------------------------------------------------------------------*/

#import "UQExtension.h"
#import "UQProject.h"

typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_idscript(void);
const TSLanguage *tree_sitter_iddecl(void);

@implementation UQExtension {
    NSBundle *_bundle;
    NSMapTable<id<UDWorkbench>, UQProject *> *_projects;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    _projects = [NSMapTable weakToStrongObjectsMapTable];
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

- (id<UDFileSystemProvider>)workbench:(id<UDWorkbench>)workbench fileSystemProviderForScheme:(NSString *)scheme {
    return [scheme isEqualToString:@"quarry"] ? [self projectOfWorkbench:workbench] : nil;
}

@end
