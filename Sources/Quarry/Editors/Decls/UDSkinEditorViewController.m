#import "UDSkinEditorViewController.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "idFileSystem.h"

static UDDiagnosticSource const UDSkinReferencesSource = @"references";

@implementation UDSkinEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDSkinEditorView" bundle:[NSBundle bundleForClass:[UDSkinEditorViewController class]]];
}

- (UDDeclSkin *)skin {
    return (UDDeclSkin *)self.declObject;
}

- (void)editingContextDidChange {
    [self checkReferences];
}

#pragma mark - The lists

/// @a element added after the selection of @a controller (at the end without
/// one), in the skin's @a key; or the selection taken off.
- (void)_addOrRemove:(NSInteger)segment element:(UDDeclElement *)element key:(NSString *)key
          controller:(NSArrayController *)controller {
    NSMutableArray *elements = [[self.skin valueForKey:key] mutableCopy] ?: [NSMutableArray array];
    NSUInteger selected = controller.selectionIndex;
    if (segment == 0) {
        NSUInteger at = selected != NSNotFound && selected < elements.count ? selected + 1 : elements.count;
        [elements insertObject:element atIndex:at];
        [self.skin setValue:elements forKey:key];
        [controller setSelectionIndex:at];
    } else if (selected != NSNotFound && selected < elements.count) {
        [self moveSelectionOffRow:selected inController:controller];
        [elements removeObjectAtIndex:selected];
        [self.skin setValue:elements forKey:key];
        [self selectRowAfterRemovingRow:selected inController:controller];
    } else {
        NSBeep();
    }
}

- (IBAction)addOrRemoveMapping:(NSSegmentedControl *)sender {
    // The engine's default skin's mapping, to be edited.
    [self _addOrRemove:sender.selectedSegment element:[UDSkinMapping mappingFrom:@"*" to:@"_default"]
                   key:@"mappings" controller:self.mappingsController];
}

- (IBAction)addOrRemoveModel:(NSSegmentedControl *)sender {
    [self _addOrRemove:sender.selectedSegment element:[UDSkinModel modelWithPath:@"models/"]
                   key:@"associatedModels" controller:self.modelsController];
    if (sender.selectedSegment == 0 && self.modelsController.selectionIndex != NSNotFound) {
        [self.modelsTable editColumn:0 row:(NSInteger)self.modelsController.selectionIndex withEvent:nil select:YES];
    }
}

#pragma mark - References

- (void)checkReferences {
    if (self.skin == nil || self.diagnosticStore == nil) return;
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    [self removeDiagnosticTargets];

    NSArray<UDSkinMapping *> *mappings = self.skin.mappings;
    for (NSUInteger row = 0; row < mappings.count; row++) {
        UDSkinMapping *mapping = mappings[row];
        for (NSString *material in @[mapping.from ?: @"", mapping.to ?: @""]) {
            if ([material isEqualToString:@"*"] || [self materialExists:material]) continue;
            UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:material] column:0
                message:[NSString stringWithFormat:@"Material “%@” is neither a decl nor an image: the engine makes it a default material", material]
                severity:UDDiagnosticSeverityWarning source:UDSkinReferencesSource];
            [items addObject:item];
            [self setTarget:@[self.mappingsController, @(row)] forDiagnostic:item];
        }
    }
    NSArray<UDSkinModel *> *models = self.skin.associatedModels;
    for (NSUInteger row = 0; row < models.count; row++) {
        UDSkinModel *model = models[row];
        // A file, by its extension: the engine picks a model's loader by it
        // (and a folder opens as a file on macOS).
        NSString *path = model.path ?: @"";
        if (path.pathExtension.length > 0 && ![path hasSuffix:@"/"] &&
            [self.workspace.fileSystem readFile:path buffer:NULL timestamp:NULL error:NULL] >= 0) continue;
        UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:path] column:0
            message:[NSString stringWithFormat:@"Model “%@” is not found", path]
            severity:UDDiagnosticSeverityError source:UDSkinReferencesSource];
        [items addObject:item];
        [self setTarget:@[self.modelsController, @(row)] forDiagnostic:item];
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDSkinReferencesSource];
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    NSArray *target = [self targetForDiagnostic:diagnostic];
    if (target == nil) return;
    NSArrayController *controller = target[0];
    // By its row: an edit puts a copy of the element in its place, the row
    // the same.
    NSUInteger index = [target[1] unsignedIntegerValue];
    if (index >= [[controller arrangedObjects] count]) return;
    [controller setSelectionIndex:index];
    NSTableView *table = controller == self.mappingsController ? self.mappingsTable : self.modelsTable;
    [table scrollRowToVisible:(NSInteger)index];
    [table.window makeFirstResponder:table];
}

#pragma mark - Pickers

/// A mapping's materials (the one replaced, its replacement), a model the
/// skin is for: the chosen row's.
- (UDReferenceField *)referenceFieldForTag:(NSInteger)tag {
    switch (tag) {
        case 1: return [UDReferenceField fieldTitled:@"The material replaced" key:@"from" controller:self.mappingsController kind:UDReferenceMaterials];
        case 2: return [UDReferenceField fieldTitled:@"The material it is replaced with" key:@"to" controller:self.mappingsController kind:UDReferenceMaterials];
        case 3: return [UDReferenceField fieldTitled:@"A model the skin is for" key:@"path" controller:self.modelsController kind:UDReferenceModels];
    }
    return nil;
}

@end
