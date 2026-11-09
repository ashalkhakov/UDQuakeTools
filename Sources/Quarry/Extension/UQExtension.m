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
#import "UQRunning.h"
#import "UDTabBadge.h"
#import "UDGuiEditorViewController.h"
#import "UDTransportController.h"
#import "UDBaseEditorViewController.h"
#import "UDDeclEditorViewController.h"

typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_idscript(void);
const TSLanguage *tree_sitter_iddecl(void);

/// The README's screenshots asked for ($UQ_OPEN): editors are remembered for it.
static BOOL UQScreenshotScene(void) {
    return NSProcessInfo.processInfo.environment[@"UQ_OPEN"].length > 0;
}

@implementation UQExtension {
    NSBundle *_bundle;
    NSMapTable<id<UDWorkbench>, UQProject *> *_projects;
    NSMapTable<id<UDWorkbench>, UQCommands *> *_commands;
    __weak UQEditorHost *_lastHost;     // the editor made last ($UQ_OPEN's front one)
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

/// A Quarry project's: its game run, its scripts debugged (UQRunning.h).
- (NSArray<Class> *)buildSystemClasses {
    return @[ [UQBuildSystem class] ];
}

- (NSArray<Class> *)debuggerClasses {
    return @[ [UQScriptDebugger class] ];
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
    // $UQ_OPEN, URLs separated by spaces (the README's screenshots,
    // docs/building.md): once the game has started, the Decls navigator
    // shown, each URL in a tab, the last one in front with its editor's
    // first inspector ($UQ_INSPECTOR: the one of that title); $UQ_GUI_DESIGN,
    // a named event: that GUI editor in Design, the event sent (NoIntro: the
    // menu, not its intro's black), two seconds into its time; $UQ_DEBUG:
    // then debugging started, as Product > Debug
    NSString *open = NSProcessInfo.processInfo.environment[@"UQ_OPEN"];
    if (open.length) {
        __weak id<UDWorkbench> weakWorkbench = workbench;
        [project whenStarted:^(UDGameWorkspace *workspace) {
            [weakWorkbench showNavigatorOfExtension:self];
            for (NSString *string in [open componentsSeparatedByString:@" "]) {
                NSURL *url = string.length ? [NSURL URLWithString:string] : nil;
                if (url) [weakWorkbench showURL:url];
            }
            // the front editor's own inspector rather than the document's
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *title = NSProcessInfo.processInfo.environment[@"UQ_INSPECTOR"];
                NSViewController *inspector = self->_lastHost.inspectorViewControllers.firstObject;
                if (title.length) [self->_lastHost showInspectorPaneTitled:title];
                else if (inspector) [weakWorkbench showEditorInspector:inspector];
                NSString *event = NSProcessInfo.processInfo.environment[@"UQ_GUI_DESIGN"];
                UDGuiEditorViewController *gui = (UDGuiEditorViewController *)self->_lastHost.editor;
                if (event.length && [gui isKindOfClass:[UDGuiEditorViewController class]]) [self _design:gui event:event tries:50];
                id controller = weakWorkbench.window.windowController;
                if (NSProcessInfo.processInfo.environment[@"UQ_DEBUG"].length && [controller respondsToSelector:@selector(startDebugging:)]) {
                    [NSApp sendAction:@selector(startDebugging:) to:controller from:nil];
                }
            });
        }];
    }
    return project;
}

/// $UQ_GUI_DESIGN's scene, once the GUI's time has two seconds (tries: tenths
/// of a second left to wait for it).
- (void)_design:(UDGuiEditorViewController *)gui event:(NSString *)event tries:(int)tries {
    NSSlider *slider = gui.transport.timeSlider;
    if (slider.maxValue < 2000 && tries > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
            [self _design:gui event:event tries:tries - 1];
        });
        return;
    }
    gui.modeControl.selectedSegment = 1;
    [gui changeMode:gui.modeControl];
    NSMenuItem *item = [gui.namedEventPopUp itemWithTitle:event];
    if (item) [NSApp sendAction:item.action to:item.target from:item];
    slider.doubleValue = MIN(2000, slider.maxValue);
    [NSApp sendAction:slider.action to:slider.target from:slider];
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
/// Declaration, the GUI editor's; in a folder that is no Quarry project, New
/// Quarry Workspace….
- (NSArray<NSMenuItem *> *)editorMenuItemsForWorkbench:(id<UDWorkbench>)workbench {
    UQProject *project = [self projectOfWorkbench:workbench];
    NSURL *folder = workbench.project.folderURL;
    if (!project && !folder) return @[];
    UQCommands *commands = [_commands objectForKey:workbench];
    if (!commands) {
        // a folder that is no Quarry project: New Quarry Workspace… alone
        commands = project ? [[UQCommands alloc] initWithProject:project extension:self] : [[UQCommands alloc] initWithFolder:folder];
        [_commands setObject:commands forKey:workbench];
    }
    return commands.menuItems;
}

/// The Decls navigator's segment: Quarry's icon.
- (NSImage *)navigatorImage {
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:[_bundle pathForResource:@"Quarry" ofType:@"png"] ?: @""];
    icon.size = NSMakeSize(16, 16);
    return icon.isValid ? icon : nil;
}

/// Its segment in the bottom area (Find in Decls'): Quarry's badge.
- (NSImage *)bottomAreaImage {
    return UDTabBadge(@"Q", 0.55, 0.36, 0.16);
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
    UDGameWorkspace *workspace = [self projectOfWorkbench:workbench].workspace;
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
        UQEditorHost *host = [[UQEditorHost alloc] initWithEditor:editor document:document workbench:workbench];
        if (UQScreenshotScene()) _lastHost = host;
        return host;
    }
    if (![document.customDocument isKindOfClass:[UQDeclDocument class]]) return nil;
    UQDeclDocument *decl = (UQDeclDocument *)document.customDocument;
    UDBaseEditorViewController *editor = [UDBaseEditorViewController editorViewControllerForWorkspaceItem:decl.item
                                                                                             inWorkspace:decl.workspace];
    if (![editor isKindOfClass:[UDDeclEditorViewController class]]) return nil;
    // the custom document's model, the one its editor edits
    [(UDDeclEditorViewController *)editor setDocument:decl.declDocument];
    UQEditorHost *host = [[UQEditorHost alloc] initWithEditor:editor document:document workbench:workbench];
    if (UQScreenshotScene()) _lastHost = host;
    return host;
}

@end
