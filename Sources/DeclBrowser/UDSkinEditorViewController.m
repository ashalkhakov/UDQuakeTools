#import "UDSkinEditorViewController.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "idFileSystem.h"

static UDDiagnosticSource const UDSkinReferencesSource = @"references";

/// The lines of a skin attribute (mappings, models), without empty ones.
static NSArray<NSString *> *UDSkinLines(NSString *text) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [lines addObject:trimmed];
    }
    return lines;
}

@interface UDSkinEditorViewController ()
@end

@implementation UDSkinEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDSkinEditorView" bundle:[NSBundle bundleForClass:[UDSkinEditorViewController class]]];
}

- (UDDeclSkin *)skin {
    return (UDDeclSkin *)self.declObject;
}

- (NSArray<NSArray<NSString *> *> *)mappings {
    NSMutableArray<NSArray<NSString *> *> *mappings = [NSMutableArray array];
    for (NSString *line in UDSkinLines(self.skin.mappings)) {
        NSRange space = [line rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        if (space.location == NSNotFound) continue;
        NSString *to = [[line substringFromIndex:NSMaxRange(space)]
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [mappings addObject:@[[line substringToIndex:space.location], to]];
    }
    return mappings;
}

- (NSArray<NSString *> *)models {
    return UDSkinLines(self.skin.associatedModels);
}

/// Written back: one edit, one undo, the tab edited.
- (void)_setMappings:(NSArray<NSArray<NSString *> *> *)mappings {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:mappings.count];
    for (NSArray<NSString *> *mapping in mappings) [lines addObject:[NSString stringWithFormat:@"%@ %@", mapping[0], mapping[1]]];
    self.skin.mappings = [lines componentsJoinedByString:@"\n"];
    [self editingContextDidChange];                     // now: the context tells at the end of the event
}

- (void)_setModels:(NSArray<NSString *> *)models {
    self.skin.associatedModels = [models componentsJoinedByString:@"\n"];
    [self editingContextDidChange];
}

- (void)editingContextDidChange {
    [self.mappingsTable reloadData];
    [self.modelsTable reloadData];
    [self checkReferences];
}

#pragma mark - The lists

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)(tableView == self.mappingsTable ? self.mappings.count : self.models.count);
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == self.mappingsTable) {
        NSArray<NSArray<NSString *> *> *mappings = self.mappings;
        if (row < 0 || row >= (NSInteger)mappings.count) return nil;
        return mappings[(NSUInteger)row][[column.identifier isEqualToString:@"from"] ? 0 : 1];
    }
    NSArray<NSString *> *models = self.models;
    return row >= 0 && row < (NSInteger)models.count ? models[(NSUInteger)row] : nil;
}

/// A name the decl can hold: one token, not empty.
static BOOL UDSkinNameIsValid(NSString *name) {
    return name.length > 0 && [name rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSString *name = [[object description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!UDSkinNameIsValid(name)) {
        NSBeep();                                       // it would break the decl: as it was
        return;
    }
    if (tableView == self.mappingsTable) {
        NSMutableArray<NSArray<NSString *> *> *mappings = [self.mappings mutableCopy];
        if (row < 0 || row >= (NSInteger)mappings.count) return;
        NSMutableArray<NSString *> *mapping = [mappings[(NSUInteger)row] mutableCopy];
        mapping[[column.identifier isEqualToString:@"from"] ? 0 : 1] = name;
        mappings[(NSUInteger)row] = mapping;
        [self _setMappings:mappings];
    } else {
        NSMutableArray<NSString *> *models = [self.models mutableCopy];
        if (row < 0 || row >= (NSInteger)models.count) return;
        models[(NSUInteger)row] = name;
        [self _setModels:models];
    }
}

- (IBAction)addOrRemoveMapping:(NSSegmentedControl *)sender {
    NSMutableArray<NSArray<NSString *> *> *mappings = [self.mappings mutableCopy];
    NSInteger selected = self.mappingsTable.selectedRow;
    if (sender.selectedSegment == 0) {
        // The engine's default skin's mapping, to be edited.
        NSUInteger at = selected >= 0 ? (NSUInteger)selected + 1 : mappings.count;
        [mappings insertObject:@[@"*", @"_default"] atIndex:at];
        [self _setMappings:mappings];
        [self.mappingsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:at] byExtendingSelection:NO];
    } else if (selected >= 0 && selected < (NSInteger)mappings.count) {
        [mappings removeObjectAtIndex:(NSUInteger)selected];
        [self _setMappings:mappings];
    } else {
        NSBeep();
    }
}

- (IBAction)addOrRemoveModel:(NSSegmentedControl *)sender {
    NSMutableArray<NSString *> *models = [self.models mutableCopy];
    NSInteger selected = self.modelsTable.selectedRow;
    if (sender.selectedSegment == 0) {
        NSUInteger at = selected >= 0 ? (NSUInteger)selected + 1 : models.count;
        [models insertObject:@"models/" atIndex:at];
        [self _setModels:models];
        [self.modelsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:at] byExtendingSelection:NO];
        [self.modelsTable editColumn:0 row:(NSInteger)at withEvent:nil select:YES];
    } else if (selected >= 0 && selected < (NSInteger)models.count) {
        [models removeObjectAtIndex:(NSUInteger)selected];
        [self _setModels:models];
    } else {
        NSBeep();
    }
}

#pragma mark - References

/// A material the engine finds: a decl, one of its own ("_default"), or an
/// image of that name, which it makes a material of.
- (BOOL)_materialExists:(NSString *)name {
    if ([name hasPrefix:@"_"]) return YES;
    idDeclManager *declManager = self.workspace.declManager;
    if ([declManager findDeclWithoutParsing:DECL_MATERIAL name:name makeDefault:NO] != nil) return YES;
    idFileSystem *fileSystem = self.workspace.fileSystem;
    NSString *base = name.pathExtension.length > 0 ? name.stringByDeletingPathExtension : name;
    for (NSString *extension in @[@"tga", @"png", @"jpg", @"dds"]) {
        if ([fileSystem readFile:[base stringByAppendingPathExtension:extension] buffer:NULL timestamp:NULL error:NULL] >= 0) return YES;
    }
    return NO;
}

- (void)checkReferences {
    if (self.skin == nil || self.diagnosticStore == nil) return;
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    [self removeDiagnosticTargets];

    NSArray<NSArray<NSString *> *> *mappings = self.mappings;
    for (NSUInteger row = 0; row < mappings.count; row++) {
        for (NSString *material in mappings[row]) {
            if ([material isEqualToString:@"*"] || [self _materialExists:material]) continue;
            UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:material] column:0
                message:[NSString stringWithFormat:@"Material “%@” is neither a decl nor an image: the engine makes it a default material", material]
                severity:UDDiagnosticSeverityWarning source:UDSkinReferencesSource];
            [items addObject:item];
            [self setTarget:@[self.mappingsTable ?: [NSNull null], @(row)] forDiagnostic:item];
        }
    }
    NSArray<NSString *> *models = self.models;
    for (NSUInteger row = 0; row < models.count; row++) {
        // A file, by its extension: the engine picks a model's loader by it
        // (and a folder opens as a file on macOS).
        if (models[row].pathExtension.length > 0 && ![models[row] hasSuffix:@"/"] &&
            [self.workspace.fileSystem readFile:models[row] buffer:NULL timestamp:NULL error:NULL] >= 0) continue;
        UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:models[row]] column:0
            message:[NSString stringWithFormat:@"Model “%@” is not found", models[row]]
            severity:UDDiagnosticSeverityError source:UDSkinReferencesSource];
        [items addObject:item];
        [self setTarget:@[self.modelsTable ?: [NSNull null], @(row)] forDiagnostic:item];
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDSkinReferencesSource];
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    NSArray *target = [self targetForDiagnostic:diagnostic];
    if (![target.firstObject isKindOfClass:[NSTableView class]]) return;
    NSTableView *table = target[0];
    NSInteger row = [target[1] integerValue];
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [table scrollRowToVisible:row];
    [table.window makeFirstResponder:table];
}

@end
