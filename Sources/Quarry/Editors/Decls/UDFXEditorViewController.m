#import "UDFXEditorViewController.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "idFileSystem.h"
#import "UDFXTimelineView.h"
#import "UDParticlePreview.h"
#import "UDTransportController.h"

static UDDiagnosticSource const UDFXReferencesSource = @"references";
/// An action dragged in the list: its row.
static NSPasteboardType const UDFXActionRowType = @"org.udquaketools.fx-action-row";

@interface UDFXEditorViewController ()
@property (nonatomic, strong, readwrite, nullable) UDTransportController *transport;
@property (nonatomic, strong, readwrite, nullable) UDParticlePreview *preview;
@property (nonatomic, copy, nullable) NSArray<UDEditorPane *> *panes;
@property (nonatomic) BOOL observingSelection;
@end

@implementation UDFXEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDFXEditorView" bundle:[NSBundle bundleForClass:[UDFXEditorViewController class]]];
}

- (UDDeclFX *)fx {
    return (UDDeclFX *)self.declObject;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.actionsController addObserver:self forKeyPath:@"selectionIndexes" options:0 context:NULL];
    self.observingSelection = YES;
    [self.actionsTable registerForDraggedTypes:@[UDFXActionRowType]];
    // each column from its top
    for (NSScrollView *scroll in @[self.effectScroll ?: [NSNull null], self.actionScroll ?: [NSNull null]]) {
        if (![scroll isKindOfClass:[NSScrollView class]]) continue;
        NSView *document = scroll.documentView;
        [document scrollPoint:NSMakePoint(0, NSMaxY(document.bounds))];
    }
    [self showInspector];
}

- (void)dealloc {
    if (_observingSelection) [_actionsController removeObserver:self forKeyPath:@"selectionIndexes"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == self.actionsController) {
        [self showInspector];
    }
}

- (NSArray<UDEditorPane *> *)inspectorPanes {
    if (self.panes == nil && self.inspectorView != nil && self.documentInspectorView != nil) {
        self.panes = @[[UDEditorPane paneWithTitle:@"FX" letters:@"FX" red:0.62 green:0.42 blue:0.68 view:self.documentInspectorView],
                       [UDEditorPane paneWithTitle:@"Action" letters:@"A" red:0.40 green:0.52 blue:0.72 view:self.inspectorView]];
    }
    return self.panes ?: @[];
}

/// The Action pane: the selected action's keywords, or "No Action Selected".
- (void)showInspector {
    NSUInteger selected = self.actionsController.selectionIndex;
    BOOL action = selected != NSNotFound && selected < self.fx.actions.count;
    [self.inspectorTabs selectTabViewItemWithIdentifier:action ? @"action" : @"none"];
}

- (IBAction)showSelectionInspector:(id)sender {
    NSUInteger selected = self.actionsController.selectionIndex;
    if (selected != NSNotFound && selected < self.fx.actions.count) [self showInspectorPaneTitled:@"Action"];
}

- (void)declDidLoad {
    // the FX's keywords first, no action chosen
    [self.actionsController setSelectionIndexes:[NSIndexSet indexSet]];
    if (self.previewView != nil) {
        self.preview = [[UDParticlePreview alloc] initWithImageView:self.previewView workspace:self.workspace];
        self.preview.target = self;
        self.preview.action = @selector(previewDidDraw:);
        self.transport = [[UDTransportController alloc] init];
        self.transport.playable = self.preview;
        self.preview.transport = self.transport;
        [self.transport installInView:self.transportView];
        self.timelineView.target = self;
        self.timelineView.action = @selector(scrubTimeline:);
    }
}

- (void)editingContextDidChange {
    [self checkReferences];
    self.preview.fxActions = self.fx.actions;
    self.timelineView.actions = self.fx.actions;
    self.timelineView.duration = self.preview.fxDuration;
}

/// A click or a drag on the timeline: the preview paused there.
- (void)scrubTimeline:(UDFXTimelineView *)timeline {
    [self.preview seekTo:timeline.scrubTime];
}

/// The preview's frame drawn: the timeline at its time.
- (void)previewDidDraw:(UDParticlePreview *)preview {
    self.timelineView.states = preview.fxStates;
    self.timelineView.time = preview.time;
}

#pragma mark - The actions

- (IBAction)addOrRemoveAction:(id)sender {
    NSInteger segment = [sender respondsToSelector:@selector(selectedSegment)] ? [sender selectedSegment] : 0;
    NSMutableArray<UDFXAction *> *actions = [self.fx.actions mutableCopy] ?: [NSMutableArray array];
    NSUInteger selected = self.actionsController.selectionIndex;
    if (segment == 0) {
        // idDeclFX::DefaultDefinition's action.
        NSData *text = [[UDDeclFX ud_defaultDefinition] dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *values = [UDDeclFX ud_parseValuesFromText:text name:@"" fileName:nil lineNum:1 fileSystem:nil error:NULL];
        UDFXAction *action = [values[@"actions"] firstObject] ?: [[UDFXAction alloc] init];
        NSUInteger at = selected != NSNotFound && selected < actions.count ? selected + 1 : actions.count;
        [actions insertObject:action atIndex:at];
        self.fx.actions = actions;
        [self.actionsController setSelectionIndex:at];
    } else if (selected != NSNotFound && selected < actions.count) {
        [self moveSelectionOffRow:selected inController:self.actionsController];
        [actions removeObjectAtIndex:selected];
        self.fx.actions = actions;
        [self selectRowAfterRemovingRow:selected inController:self.actionsController];
    } else {
        NSBeep();
    }
}

#pragma mark - Dragging an action to another place

// The rows are the array controller's (the content binding).
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[self.actionsController.arrangedObjects count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return nil;
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pasteboard {
    if (rows.count != 1) return NO;
    [pasteboard declareTypes:@[UDFXActionRowType] owner:nil];
    [pasteboard setString:[NSString stringWithFormat:@"%lu", (unsigned long)rows.firstIndex] forType:UDFXActionRowType];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    if ([info draggingSource] != tableView || [[info draggingPasteboard] stringForType:UDFXActionRowType] == nil) {
        return NSDragOperationNone;
    }
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {
    NSString *from = [[info draggingPasteboard] stringForType:UDFXActionRowType];
    if (from == nil) return NO;
    return [self moveActionAtIndex:(NSUInteger)from.integerValue toRow:(NSUInteger)row];
}

- (BOOL)moveActionAtIndex:(NSUInteger)index toRow:(NSUInteger)row {
    NSMutableArray<UDFXAction *> *actions = [self.fx.actions mutableCopy];
    if (index >= actions.count || row > actions.count) return NO;
    NSUInteger to = row > index ? row - 1 : row;
    if (to == index) return NO;
    UDFXAction *action = actions[index];
    [actions removeObjectAtIndex:index];
    [actions insertObject:action atIndex:to];
    self.fx.actions = actions;
    [self.actionsController setSelectionIndex:to];
    return YES;
}

#pragma mark - Pickers

/// The names of the actions before @a action (of @a kinds, if given).
- (NSArray<NSString *> *)_actionNamesBefore:(UDFXAction *)action kinds:(NSArray<NSString *> *)kinds details:(NSMutableArray<NSString *> *)details {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UDFXAction *other in self.fx.actions) {
        if (other == action && kinds != nil) break;
        if (other == action || other.name.length == 0) continue;
        if (kinds != nil && ![kinds containsObject:other.kind ?: @""]) continue;
        [names addObject:other.name];
        [details addObject:other.kind ?: @""];
    }
    return names;
}

/// What an action uses, by its kind (ParseSingleFXAction's): a light's or
/// a decal's material, a model, a particle, a sound shader, an entityDef,
/// or an earlier action's name.
- (UDReferenceField *)referenceFieldForTag:(NSInteger)tag {
    NSArray<UDFXAction *> *selected = self.actionsController.selectedObjects;
    UDFXAction *action = selected.firstObject;
    if (action == nil) return nil;
    NSArrayController *actions = self.actionsController;
    if (tag == 2) {
        UDReferenceField *field = [UDReferenceField fieldTitled:@"The action that starts it" key:@"fire" controller:actions kind:UDReferenceNames];
        NSMutableArray<NSString *> *details = [NSMutableArray array];
        field.names = [self _actionNamesBefore:action kinds:nil details:details];
        field.details = details;
        return field;
    }
    if (tag != 1) return nil;
    NSString *kind = action.kind ?: @"";
    if ([@[@"light", @"decal", @"attachlight"] containsObject:kind]) {
        return [UDReferenceField fieldTitled:@"A material" key:@"data" controller:actions kind:UDReferenceMaterials];
    }
    if ([kind isEqualToString:@"model"]) {
        return [UDReferenceField fieldTitled:@"A model" key:@"data" controller:actions kind:UDReferenceModels];
    }
    if ([@[@"uselight", @"usemodel"] containsObject:kind]) {
        UDReferenceField *field = [UDReferenceField fieldTitled:@"An earlier action" key:@"data" controller:actions kind:UDReferenceNames];
        NSMutableArray<NSString *> *details = [NSMutableArray array];
        field.names = [self _actionNamesBefore:action kinds:[kind isEqualToString:@"uselight"] ? @[@"light"] : @[@"model"] details:details];
        field.details = details;
        return field;
    }
    declType_t type = [kind isEqualToString:@"particle"] ? DECL_PARTICLE
                    : [kind isEqualToString:@"sound"] ? DECL_SOUND
                    : [@[@"attachentity", @"launch", @"shockwave"] containsObject:kind] ? DECL_ENTITYDEF : DECL_MAX_TYPES;
    if (type == DECL_MAX_TYPES) return nil;
    UDReferenceField *field = [UDReferenceField fieldTitled:[NSString stringWithFormat:@"What the %@ uses", kind] key:@"data"
                                                 controller:actions kind:UDReferenceDecls];
    field.declType = type;
    return field;
}

#pragma mark - References

- (BOOL)_declExists:(declType_t)type named:(NSString *)name {
    return [self.workspace.declManager findDeclWithoutParsing:type name:name makeDefault:NO] != nil;
}

- (BOOL)_fileExists:(NSString *)path {
    return [self.workspace.fileSystem readFile:path buffer:NULL timestamp:NULL error:NULL] >= 0;
}

/// idRenderModelManagerLocal::GetModel's loaders, by extension.
- (nullable NSString *)_modelProblem:(NSString *)path {
    if ([path hasPrefix:@"_"]) return nil;                         // its own, "_default"
    NSString *extension = path.pathExtension.lowercaseString;
    if ([@[@"ase", @"lwo", @"flt", @"ma", @"md5mesh", @"md3"] containsObject:extension]) {
        return [self _fileExists:path] ? nil : [NSString stringWithFormat:@"Model “%@” is not found", path];
    }
    if ([extension isEqualToString:@"prt"]) {
        // idRenderModelPrt::InitFromFile: the particle decl of its name.
        return [self _declExists:DECL_PARTICLE named:path] ? nil : [NSString stringWithFormat:@"No particle “%@”", path];
    }
    if ([extension isEqualToString:@"liquid"]) {
        return nil;
    }
    if (extension.length > 0) {
        return [NSString stringWithFormat:@"unknown model type '%@'", path];
    }
    return [NSString stringWithFormat:@"Model “%@” has no extension: the engine makes it a default model", path];
}

- (nullable NSString *)_problemOfAction:(UDFXAction *)action before:(NSArray<UDFXAction *> *)earlier {
    NSString *kind = action.kind, *data = action.data ?: @"";
    if ([kind isEqualToString:@"light"] || [kind isEqualToString:@"attachlight"] || [kind isEqualToString:@"decal"]) {
        return [self materialExists:data] ? nil
            : [NSString stringWithFormat:@"Material “%@” is neither a decl nor an image: the engine makes it a default material", data];
    }
    if ([kind isEqualToString:@"model"] || [kind isEqualToString:@"particle"] || [kind isEqualToString:@"attachentity"]) {
        return [self _modelProblem:data];
    }
    if ([kind isEqualToString:@"launch"] || [kind isEqualToString:@"shockwave"]) {
        return [self _declExists:DECL_ENTITYDEF named:data] ? nil : [NSString stringWithFormat:@"No entityDef “%@”", data];
    }
    if ([kind isEqualToString:@"sound"]) {
        // FindSound makes a shader of a name no decl defines: its .wav.
        if ([self _declExists:DECL_SOUND named:data]) return nil;
        NSString *wav = data.pathExtension.length > 0 ? data : [data stringByAppendingPathExtension:@"wav"];
        NSString *ogg = [wav.stringByDeletingPathExtension stringByAppendingPathExtension:@"ogg"];
        return [self _fileExists:wav] || [self _fileExists:ogg] ? nil
            : [NSString stringWithFormat:@"No sound shader or sample “%@”", data];
    }
    if ([kind isEqualToString:@"uselight"] || [kind isEqualToString:@"usemodel"]) {
        // The sibling ParseSingleFXAction looks for: an earlier action by that name.
        for (UDFXAction *other in earlier) {
            if ([other.name caseInsensitiveCompare:data] == NSOrderedSame) return nil;
        }
        return [NSString stringWithFormat:@"No earlier action named “%@” to use", data];
    }
    return nil;
}

- (void)checkReferences {
    UDDeclFX *fx = self.fx;
    if (fx == nil || self.diagnosticStore == nil) return;
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    [self removeDiagnosticTargets];

    NSArray<UDFXAction *> *actions = fx.actions;
    for (NSUInteger row = 0; row < actions.count; row++) {
        NSString *problem = [self _problemOfAction:actions[row] before:[actions subarrayWithRange:NSMakeRange(0, row)]];
        if (problem == nil) continue;
        UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:actions[row].data ?: @""] column:0
            message:[NSString stringWithFormat:@"Action %lu: %@", (unsigned long)row, problem]
            severity:UDDiagnosticSeverityWarning source:UDFXReferencesSource];
        [items addObject:item];
        [self setTarget:@(row) forDiagnostic:item];
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDFXReferencesSource];
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    NSNumber *row = [self targetForDiagnostic:diagnostic];
    if (row == nil || row.unsignedIntegerValue >= self.fx.actions.count) return;
    [self.actionsController setSelectionIndex:row.unsignedIntegerValue];
    [self.actionsTable scrollRowToVisible:row.integerValue];
    [self.view.window makeFirstResponder:self.actionsTable];
    [self showSelectionInspector:nil];
}

@end
