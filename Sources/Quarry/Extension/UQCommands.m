/*---------------------------------------------------------------------------------------------
 *  UQCommands.m
 *--------------------------------------------------------------------------------------------*/

#import "UQCommands.h"
#import "UQProject.h"
#import "UDGameWorkspace.h"
#import "UDDeclManagedObjects.h"
#import "UDDeclTextChecker.h"
#import "UDNewDeclWindowController.h"
#import "UDTextPromptPanel.h"
#import "idDeclManager.h"
#import "UQFindViewController.h"
#import "UDWorkspaceSettingsWindowController.h"

static UDDiagnosticSource const UQDiagnosticSourceDeclTest = @"test";

@implementation UQCommands {
    NSArray<NSMenuItem *> *_menuItems;
    __weak id<UDExtension> _extension;
    UQFindViewController *_find;
    UDWorkspaceSettingsWindowController *_settings;
}

- (instancetype)initWithProject:(UQProject *)project extension:(id<UDExtension>)extension {
    if (!(self = [super init])) return nil;
    _project = project;
    _extension = extension;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"UQEditorMenus" bundle:[NSBundle bundleForClass:[UQCommands class]]];
    [nib instantiateWithOwner:self topLevelObjects:NULL];
    _menuItems = [_menu.itemArray copy];
    [_menu removeAllItems];
    return self;
}

- (NSArray<NSMenuItem *> *)menuItems {
    return _menuItems;
}

- (UDGameWorkspace *)_workspace {
    return _project.workspace;
}

// ---------------------------------------------------------------------------
// MARK: - New decls
// ---------------------------------------------------------------------------

- (BOOL)createDeclOfTypeName:(NSString *)typeName named:(NSString *)name fileName:(NSString *)fileName error:(NSError **)error {
    NSManagedObjectContext *context = [self._workspace newDeclEditingContextWithError:error];
    if (!context) return NO;
    NSString *entityName = [UDDeclBase ud_entityNameForDeclTypeName:typeName
                                                            inModel:context.persistentStoreCoordinator.managedObjectModel];
    if (!entityName) {
        if (error) *error = [NSError errorWithDomain:@"UQCommandsErrorDomain" code:1 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"A %@ can't be made here.", typeName] }];
        return NO;
    }
    UDDeclBase *decl = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:context];
    decl.name = name;
    if (fileName.length > 0) {
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"DeclFile"];
        request.predicate = [NSPredicate predicateWithFormat:@"fileName ==[c] %@", fileName];
        NSManagedObject *file = [[context executeFetchRequest:request error:NULL] firstObject];
        if (!file) {
            file = [NSEntityDescription insertNewObjectForEntityForName:@"DeclFile" inManagedObjectContext:context];
            [file setValue:fileName forKey:@"fileName"];
        }
        [decl setValue:file forKey:@"sourceFile"];
    }
    return [context save:error];
}

/// The made decl: the tree read again, it in its tab.
- (void)_show:(NSString *)typeName name:(NSString *)name {
    [_project reloadTree];
    [_project.workbench showURL:[UQProject URLOfDeclType:typeName name:name]];
}

- (void)_present:(NSError *)error {
    [[NSAlert alertWithError:error] runModal];
}

/// DialogDeclNew's type, name and file; the decl starts from its type's
/// default definition, in that file (a new one, or one the decls are in).
- (IBAction)newDecl:(id)sender {
    UDNewDeclWindowController *dialog = [[UDNewDeclWindowController alloc] initWithDeclManager:self._workspace.declManager typeName:nil];
    if ([dialog runModal] != NSModalResponseOK) return;
    NSError *error = nil;
    if (![self createDeclOfTypeName:dialog.typeName named:dialog.declName fileName:dialog.fileName error:&error]) {
        [self _present:error];
        return;
    }
    [self _show:dialog.typeName name:dialog.declName];
}

- (IBAction)newPDA:(id)sender {
    [self _newDeclOfTypeName:@"pda" title:@"New PDA" fileName:@"newpdas/<name>.pda"];
}

- (IBAction)newSkin:(id)sender {
    [self _newDeclOfTypeName:@"skin" title:@"New Skin" fileName:@"skins/<name>.skin"];
}

/// A decl of its own name, in a file of its own (the type's folder, where
/// the store puts a new decl).
- (void)_newDeclOfTypeName:(NSString *)typeName title:(NSString *)title fileName:(NSString *)fileName {
    idDeclManager *declManager = self._workspace.declManager;
    declType_t type = [declManager declTypeFromName:typeName];
    NSString *value = [declManager newName:type base:[typeName stringByAppendingString:@"_"]];
    while (YES) {
        NSString *entered = [UDTextPromptPanel runModalPromptWithTitle:title
            message:[NSString stringWithFormat:@"It gets a file of its own, %@, written when it is saved.", fileName]
            initialValue:value okButtonTitle:@"Create"];
        if (!entered) return;
        value = entered;
        NSString *name = [entered stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!name.length) continue;
        if ([declManager findDeclWithoutParsing:type name:name makeDefault:NO]) {
            NSAlert *taken = [[NSAlert alloc] init];
            taken.messageText = @"Name already in use";
            taken.informativeText = [NSString stringWithFormat:@"A %@ decl named “%@” already exists. Choose a different name.", typeName, name];
            [taken runModal];
            continue;
        }
        NSError *error = nil;
        if (![self createDeclOfTypeName:typeName named:name fileName:nil error:&error]) {
            [self _present:error];
            return;
        }
        [self _show:typeName name:name];
        return;
    }
}

// ---------------------------------------------------------------------------
// MARK: - Test Declaration (DialogDeclEditor's)
// ---------------------------------------------------------------------------

/// The front document, when it is one of the project's decls: its type and
/// name through *typeName and *name.
- (nullable UDCodeDocument *)_declDocument:(NSString **)typeName name:(NSString **)name {
    UDCodeDocument *document = _project.workbench.selectedDocument;
    NSString *path = nil;
    if (![UQProject parseURL:document.URL typeName:typeName name:name path:&path] || path) return nil;
    return document;
}

- (NSArray<UDDiagnosticItem *> *)problemsOfDeclDocument:(UDCodeDocument *)document {
    NSString *typeName = nil, *name = nil;
    [UQProject parseURL:document.URL typeName:&typeName name:&name path:NULL];
    // the custom document's text is its objects' now; a text document's, its text
    NSString *text = [document.customDocument respondsToSelector:@selector(textOfDocument)]
        ? [document.customDocument textOfDocument] : [document.textModel getValue];
    // TestDecl's braces, and the lexer as the decl manager has it; then, as
    // OnBnClickedTest has the decl parse its new text, the type's parser
    NSMutableArray<UDDeclTextProblem *> *problems =
        [[UDDeclTextChecker problemsInDeclText:text ?: @"" fileSystem:self._workspace.fileSystem] mutableCopy];
    BOOL bracesHold = YES;
    for (UDDeclTextProblem *problem in problems) {
        if (problem.isError) bracesHold = NO;
    }
    NSManagedObjectModel *model = self._workspace.declStoreCoordinator.managedObjectModel;
    NSString *entityName = typeName && model ? [UDDeclBase ud_entityNameForDeclTypeName:typeName inModel:model] : nil;
    NSEntityDescription *entity = entityName ? [model.entitiesByName objectForKey:entityName] : nil;
    Class declClass = entity ? NSClassFromString(entity.managedObjectClassName) : Nil;
    if (bracesHold && [declClass isSubclassOfClass:[UDDeclBase class]] && name) {
        [problems addObjectsFromArray:[declClass ud_problemsParsingText:text name:name declManager:self._workspace.declManager]];
    }
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    for (UDDeclTextProblem *problem in problems) {
        [items addObject:[[UDDiagnosticItem alloc] initWithLine:problem.line column:0 message:problem.message
                                                       severity:problem.isError ? UDDiagnosticSeverityError : UDDiagnosticSeverityWarning
                                                         source:UQDiagnosticSourceDeclTest]];
    }
    return items;
}

- (IBAction)testDecl:(id)sender {
    UDCodeDocument *document = [self _declDocument:NULL name:NULL];
    if (!document) {
        NSBeep();
        return;
    }
    [document.diagnosticStore setDiagnostics:[self problemsOfDeclDocument:document] forSource:UQDiagnosticSourceDeclTest];
}

- (IBAction)showWorkspaceSettings:(id)sender {
    if (_settings) {
        [_settings showWindow:nil];
        return;
    }
    NSBundle *bundle = [NSBundle bundleForClass:[UQCommands class]];
    // its XIB from this bundle, it the XIB's owner
    UDWorkspaceSettingsWindowController *settings = [UDWorkspaceSettingsWindowController alloc];
    _settings = [settings initWithWindowNibPath:[bundle pathForResource:@"UDWorkspaceSettings" ofType:@"nib"]
                                                    ?: [bundle pathForResource:@"UDWorkspaceSettings" ofType:@"xib"]
                                          owner:settings];
    _settings.workspace = self._workspace;
    _settings.target = self;
    _settings.action = @selector(_settingsDidFinish:);
    [_settings showWindow:nil];
}

- (void)_settingsDidFinish:(UDWorkspaceSettingsWindowController *)settings {
    _settings = nil;
    if (settings.result != NSModalResponseOK) return;
    NSError *error = nil;
    if (![_project applySettings:settings.scratchWorkspace.dictionaryRepresentation error:&error]) [self _present:error];
}

- (IBAction)findInDecls:(id)sender {
    if (!_find) _find = [[UQFindViewController alloc] initWithProject:_project];
    [_project.workbench showBottomAreaViewController:_find title:@"Find in Decls" extension:_extension];
    [_find.view.window makeFirstResponder:_find.searchField];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (sel_isEqual(action, @selector(testDecl:))) return [self _declDocument:NULL name:NULL] != nil;
    return self._workspace != nil;
}

@end
