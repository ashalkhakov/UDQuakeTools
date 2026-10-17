#import "UDMaterialEditorViewController.h"
#import "idDeclManager.h"
#import "UDDeclManagedObjects.h"
#import "UDDeclTextChecker.h"
#import "UDImageProgram.h"
#import "UDMaterialParser.h"
#import "UDWorkspace.h"
#import "UDParticlePreview.h"
#import "UDTransportController.h"

static UDDiagnosticSource const UDMaterialParseSource = @"parse";
static UDDiagnosticSource const UDMaterialImagesSource = @"references";
/// A stage dragged in the list: its row.
static NSPasteboardType const UDMaterialStageRowType = @"org.udquaketools.material-stage-row";

@interface UDMaterialEditorViewController ()
@property (nonatomic, strong, readwrite, nullable) UDTransportController *transport;
/// idMaterial::Parse of the text as it is now.
@property (nonatomic, strong, nullable) UDMaterialParser *parser;
@property (nonatomic) BOOL observingSelection;
@property (nonatomic, strong, readwrite, nullable) UDParticlePreview *materialPreview;
@property (nonatomic, copy) NSArray<UDEditorPane *> *panes;
@end

@implementation UDMaterialEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDMaterialEditorView" bundle:[NSBundle bundleForClass:[UDMaterialEditorViewController class]]];
}

- (UDDeclMaterial *)material {
    return (UDDeclMaterial *)self.declObject;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.stagesController addObserver:self forKeyPath:@"selectionIndexes" options:0 context:NULL];
    self.observingSelection = YES;
    [self.stagesTable registerForDraggedTypes:@[UDMaterialStageRowType]];
    // each column from its top
    for (NSScrollView *scroll in @[self.materialScroll ?: [NSNull null], self.stageScroll ?: [NSNull null]]) {
        if (![scroll isKindOfClass:[NSScrollView class]]) continue;
        NSView *document = scroll.documentView;
        [document scrollPoint:NSMakePoint(0, NSMaxY(document.bounds))];
    }
    [self showInspector];
}

- (NSArray<UDEditorPane *> *)inspectorPanes {
    if (self.panes == nil && self.inspectorView != nil) {
        self.panes = @[[UDEditorPane paneWithTitle:@"Properties" letters:@"P" red:0.62 green:0.42 blue:0.68 view:self.inspectorView]];
    }
    return self.panes ?: @[];
}

/// The inspector: the selected stage's keywords, or the material's.
- (void)showInspector {
    [self.inspectorTabs selectTabViewItemWithIdentifier:[self selectedStage] != NSNotFound ? @"stage" : @"material"];
}

- (void)dealloc {
    if (_observingSelection) [_stagesController removeObserver:self forKeyPath:@"selectionIndexes"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == self.stagesController) {
        [self showInspector];
        [self showPreview];
    }
}

- (void)declDidLoad {
    // the material's keywords first, no stage chosen
    [self.stagesController setSelectionIndexes:[NSIndexSet indexSet]];
    if (self.materialPreviewView != nil) {
        self.materialPreview = [[UDParticlePreview alloc] initWithImageView:self.materialPreviewView workspace:self.workspace];
        self.materialPreview.materialName = self.material.name;
        self.transport = [[UDTransportController alloc] init];
        self.transport.playable = self.materialPreview;
        self.materialPreview.transport = self.transport;
        [self.transport installInView:self.transportView];
        self.materialPreview.target = self;
        self.materialPreview.action = @selector(previewDidDraw:);
    }
}

/// The preview's frame drawn: why it is not lit, if it is not.
- (void)previewDidDraw:(UDParticlePreview *)preview {
    self.lightingLabel.stringValue = preview.lightingProblem ?: @"";
}

- (void)editingContextDidChange {
    [self reparse];
    [self.stagesTable reloadData];
    [self showPreview];
}

#pragma mark - The stages (MaterialDoc's AddStage, RemoveStage, MoveStage)

- (NSUInteger)selectedStage {
    NSUInteger selected = self.stagesController.selectionIndex;
    return selected != NSNotFound && selected < self.material.stages.count ? selected : NSNotFound;
}

- (IBAction)addOrRemoveStage:(id)sender {
    NSInteger segment = [sender respondsToSelector:@selector(selectedSegment)] ? [sender selectedSegment] : 0;
    NSUInteger selected = [self selectedStage];
    NSUInteger count = self.material.stages.count;
    if (segment == 0) {
        // StageView::OnAddStage: a stage named "Stage <count + 1>", last.
        [self.material ud_insertStageText:[NSString stringWithFormat:@"{\n\t\tname\t\"Stage %lu\"\n\t}", (unsigned long)count + 1]
                                  atIndex:count];
        [self.stagesController setSelectionIndex:count];
    } else if (selected != NSNotFound) {
        [self moveSelectionOffRow:selected inController:self.stagesController];
        [self.material ud_removeStageAtIndex:selected];
        [self selectRowAfterRemovingRow:selected inController:self.stagesController];
    } else {
        NSBeep();
    }
}

- (IBAction)moveStage:(id)sender {
    NSInteger segment = [sender respondsToSelector:@selector(selectedSegment)] ? [sender selectedSegment] : 0;
    NSUInteger selected = [self selectedStage];
    NSUInteger to = segment == 0 ? selected - 1 : selected + 1;
    if (selected == NSNotFound || (segment == 0 && selected == 0) || to >= self.material.stages.count) {
        NSBeep();
        return;
    }
    [self.material ud_exchangeStageAtIndex:selected withStageAtIndex:to];
    [self.stagesController setSelectionIndex:to];
}

- (IBAction)addLightingStage:(id)sender {
    // StageView's OnAddBumpmapStage, OnAddDiffuseStage, OnAddSpecualarStage
    // add the shortcut with no map, which the parse then reads past; here
    // with the image the engine gives one it has to make (AddImplicitStages'
    // _flat and _white; _black, globalImages' no-specular one).
    NSInteger tag = [sender respondsToSelector:@selector(selectedItem)] ? [[sender selectedItem] tag]
                  : [sender respondsToSelector:@selector(tag)] ? [sender tag] : 0;
    NSString *text = tag == 1 ? @"bumpmap\t_flat" : tag == 2 ? @"diffusemap\t_white" : tag == 3 ? @"specularmap\t_black" : nil;
    if (text == nil) {
        NSBeep();
        return;
    }
    NSUInteger count = self.material.stages.count;
    [self.material ud_insertStageText:text atIndex:count];
    [self.stagesController setSelectionIndex:count];
}

- (IBAction)copy:(id)sender {
    NSUInteger selected = [self selectedStage];
    if (selected == NSNotFound) {
        NSBeep();
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    // declareTypes:owner: (GNUstep has no -clearContents)
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
    [pasteboard setString:self.material.stages[selected].text forType:NSPasteboardTypeString];
}

- (IBAction)paste:(id)sender {
    NSString *text = [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        NSBeep();
        return;
    }
    NSUInteger selected = [self selectedStage];
    NSUInteger at = selected != NSNotFound ? selected + 1 : self.material.stages.count;
    NSUInteger before = self.material.stages.count;
    [self.material ud_insertStageText:text atIndex:at];
    if (self.material.stages.count == before + 1) {
        [self.stagesController setSelectionIndex:at];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(copy:)) {
        return [self selectedStage] != NSNotFound;
    }
    if (menuItem.action == @selector(paste:)) {
        return [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] != nil;
    }
    return YES;
}

#pragma mark - The stage list's names

// Its rows are its array controller's (the content binding); the Stage
// column, unbound, is the stage's name (MaterialDoc's), its shortcut's
// keyword, or "stage <row>".
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[self.stagesController.arrangedObjects count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (![tableColumn.identifier isEqualToString:@"stage"]) return nil;
    NSArray<UDMaterialStage *> *stages = self.stagesController.arrangedObjects;
    if (row < 0 || (NSUInteger)row >= stages.count) return nil;
    UDMaterialStage *stage = stages[(NSUInteger)row];
    NSString *name = [stage valueForKey:@"name"];
    if (name.length > 0) return name;
    if (stage.shortcut != nil) return stage.shortcut;
    return [NSString stringWithFormat:@"stage %ld", (long)row];
}

#pragma mark - Dragging a stage to another place (MaterialDoc's MoveStage)

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pasteboard {
    if (rows.count != 1) return NO;
    [pasteboard declareTypes:@[UDMaterialStageRowType] owner:nil];
    [pasteboard setString:[NSString stringWithFormat:@"%lu", (unsigned long)rows.firstIndex] forType:UDMaterialStageRowType];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    if ([info draggingSource] != tableView || [[info draggingPasteboard] stringForType:UDMaterialStageRowType] == nil) {
        return NSDragOperationNone;
    }
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {
    NSString *from = [[info draggingPasteboard] stringForType:UDMaterialStageRowType];
    if (from == nil) return NO;
    return [self moveStageAtIndex:(NSUInteger)from.integerValue toRow:(NSUInteger)row];
}

/// The stage at @a index to before row @a row (as a drop above it puts it),
/// a place at a time, as MoveStage moves it; it is the selection after.
- (BOOL)moveStageAtIndex:(NSUInteger)index toRow:(NSUInteger)row {
    NSUInteger count = self.material.stages.count;
    if (index >= count || row > count) return NO;
    NSUInteger to = row > index ? row - 1 : row;
    if (to == index) return NO;
    for (NSUInteger at = index; at != to; at = to > at ? at + 1 : at - 1) {
        [self.material ud_exchangeStageAtIndex:at withStageAtIndex:to > at ? at + 1 : at - 1];
    }
    [self.stagesController setSelectionIndex:to];
    return YES;
}

#pragma mark - Pickers

- (UDReferenceField *)referenceFieldForTag:(NSInteger)tag {
    switch (tag) {
        case 1: return [UDReferenceField fieldTitled:@"The stage's image" key:@"map" controller:self.stagesController kind:UDReferenceImages];
        case 2: return [UDReferenceField fieldTitled:@"A cinematic" key:@"videomap" controller:self.stagesController kind:UDReferenceVideos];
        case 3: return [UDReferenceField fieldTitled:@"The editor's image" key:@"qerEditorImage" controller:self.objectController kind:UDReferenceImages];
        case 4: return [UDReferenceField fieldTitled:@"The light's falloff image" key:@"lightFalloffImage" controller:self.objectController kind:UDReferenceImages];
        case 5: return [UDReferenceField fieldTitled:@"A GUI" key:@"guisurf" controller:self.objectController kind:UDReferenceGuis];
        case 6: return [UDReferenceField fieldTitled:@"A cube map" key:@"cubeMap" controller:self.stagesController kind:UDReferenceCubeMaps];
        case 7: return [UDReferenceField fieldTitled:@"The stage's program" key:@"program" controller:self.stagesController kind:UDReferencePrograms];
        case 8: return [UDReferenceField fieldTitled:@"The stage's vertex program" key:@"vertexProgram" controller:self.stagesController kind:UDReferencePrograms];
        case 9: return [UDReferenceField fieldTitled:@"The stage's fragment program" key:@"fragmentProgram" controller:self.stagesController kind:UDReferencePrograms];
    }
    return nil;
}

#pragma mark - Expressions

/// A stage's registers' keywords (ParseStage's), by their fields' tags.
static NSArray<NSArray<NSString *> *> *UDMaterialExpressionKeys(void) {
    return @[@[@"scroll", @"scroll"], @[@"translate", @"translate"], @[@"scale", @"scale"], @[@"centerScale", @"centerScale"],
             @[@"shear", @"shear"], @[@"rotate", @"rotate"], @[@"color", @"color"], @[@"red", @"red"], @[@"green", @"green"],
             @[@"blue", @"blue"], @[@"alpha", @"alpha"], @[@"rgb", @"rgb"], @[@"rgba", @"rgba"], @[@"alphaTest", @"alphaTest"],
             @[@"condition", @"if"]];
}

- (UDReferenceField *)expressionFieldForTag:(NSInteger)tag {
    NSArray<NSArray<NSString *> *> *keys = UDMaterialExpressionKeys();
    if (tag < 1 || tag > (NSInteger)keys.count) return nil;
    NSArray<NSString *> *key = keys[(NSUInteger)tag - 1];
    return [UDReferenceField fieldTitled:[NSString stringWithFormat:@"The stage's %@", key[1]] key:key[0]
                              controller:self.stagesController kind:UDReferenceNames];
}

/// What idMaterial::ParseTerm reads: its registers, the tables (looked up
/// as table[expression]), and the operators ParseExpressionPriority knows.
- (NSArray<UDExpressionCategory *> *)expressionCategoriesFor:(UDReferenceField *)field {
    NSMutableArray<UDExpressionEntry *> *parms = [NSMutableArray array];
    [parms addObject:[UDExpressionEntry entryNamed:@"time" insertion:nil summary:@"The game's time, in seconds."]];
    for (int i = 0; i < 12; i++) {
        [parms addObject:[UDExpressionEntry entryNamed:[NSString stringWithFormat:@"parm%d", i] insertion:nil
                                               summary:i < 4 ? @"The entity's shaderParm: its color (0-3, 1 when not set)." : @"The entity's shaderParm."]];
    }
    for (int i = 0; i < 8; i++) {
        [parms addObject:[UDExpressionEntry entryNamed:[NSString stringWithFormat:@"global%d", i] insertion:nil
                                               summary:@"A global shaderParm, the game's to set."]];
    }
    [parms addObject:[UDExpressionEntry entryNamed:@"fragmentPrograms" insertion:nil summary:@"1 when fragment programs are in use."]];
    [parms addObject:[UDExpressionEntry entryNamed:@"sound" insertion:nil summary:@"The entity's sound's amplitude."]];
    NSMutableArray<UDExpressionEntry *> *tables = [NSMutableArray array];
    for (idDeclBase *decl in [self.workspace.declManager declsOfType:DECL_TABLE forceParse:NO]) {
        [tables addObject:[UDExpressionEntry entryNamed:decl.name insertion:[decl.name stringByAppendingString:@"[ "]
                                                summary:[NSString stringWithFormat:@"A table, looked up at an expression: %@[ time ]", decl.name]]];
    }
    NSMutableArray<UDExpressionEntry *> *operators = [NSMutableArray array];
    for (NSArray<NSString *> *op in @[@[@"+", @"Adds."], @[@"-", @"Subtracts."], @[@"*", @"Multiplies."], @[@"/", @"Divides."],
                                      @[@"%", @"The remainder."], @[@"==", @"1 when equal, else 0."], @[@"!=", @"1 when not equal."],
                                      @[@">", @"1 when greater."], @[@"<", @"1 when less."], @[@">=", @"1 when greater or equal."],
                                      @[@"<=", @"1 when less or equal."], @[@"&&", @"1 when both are not 0."], @[@"||", @"1 when either is not 0."],
                                      @[@"( )", @"Groups."]]) {
        [operators addObject:[UDExpressionEntry entryNamed:op[0] insertion:[op[0] isEqualToString:@"( )"] ? @"( " : [NSString stringWithFormat:@" %@ ", op[0]]
                                                   summary:op[1]]];
    }
    UDExpressionCategory *tableCategory = [UDExpressionCategory categoryNamed:@"Tables" entries:tables];
    tableCategory.tables = YES;
    return @[[UDExpressionCategory categoryNamed:@"Parms" entries:parms], tableCategory,
             [UDExpressionCategory categoryNamed:@"Operators" entries:operators]];
}

/// The text as idMaterial::Parse reads it: in a stage of its own, its
/// keyword before it; the parse's first warning.
- (NSString *)problemWithExpression:(NSString *)text for:(UDReferenceField *)field {
    NSString *keyword = nil;
    for (NSArray<NSString *> *key in UDMaterialExpressionKeys()) {
        if ([key[0] isEqualToString:field.key]) keyword = key[1];
    }
    if (keyword == nil || [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) return nil;
    NSString *material = [NSString stringWithFormat:@"{\n\t{\n\t\tblend add\n\t\tmap _white\n\t\t%@ %@\n\t}\n}\n", keyword, text];
    UDMaterialParser *parser = [[UDMaterialParser alloc] initWithText:material name:@"_expression" declManager:self.workspace.declManager];
    UDDeclTextProblem *problem = parser.problems.firstObject;
    return problem != nil ? problem.message : nil;
}

#pragma mark - What the engine says

- (void)reparse {
    UDDeclMaterial *material = self.material;
    if (material == nil || self.diagnosticStore == nil) return;
    NSData *data = [material ud_currentText:NULL];
    NSString *text = data != nil ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (text == nil) return;
    self.parser = [[UDMaterialParser alloc] initWithText:text name:material.name declManager:self.workspace.declManager];
    self.materialPreview.materialText = text;

    [self removeDiagnosticTargets];
    NSMutableArray<UDDiagnosticItem *> *parsed = [NSMutableArray array];
    for (UDDeclTextProblem *problem in self.parser.problems) {
        [parsed addObject:[[UDDiagnosticItem alloc] initWithLine:problem.line column:0 message:problem.message
                                                        severity:problem.isError ? UDDiagnosticSeverityError : UDDiagnosticSeverityWarning
                                                          source:UDMaterialParseSource]];
    }
    [self.diagnosticStore setDiagnostics:parsed forSource:UDMaterialParseSource];

    // idImage::ActuallyLoadImage's "Couldn't load image", for each stage's.
    NSMutableArray<UDDiagnosticItem *> *images = [NSMutableArray array];
    for (UDMaterialStageInfo *stage in self.parser.stages) {
        if (stage.imageName.length == 0 || stage.textIndex < 0 || stage.cubeMap != UDCubeFiles2D) continue;
        if ([UDImageProgram imageExistsNamed:stage.imageName fileSystem:self.workspace.fileSystem]) continue;
        UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:stage.imageName] column:0
            message:[NSString stringWithFormat:@"Couldn't load image: %@", [UDImageProgram imageNameFromName:stage.imageName]]
            severity:UDDiagnosticSeverityWarning source:UDMaterialImagesSource];
        [images addObject:item];
        [self setTarget:@(stage.textIndex) forDiagnostic:item];
    }
    [self.diagnosticStore setDiagnostics:images forSource:UDMaterialImagesSource];
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    NSNumber *row = [self targetForDiagnostic:diagnostic];
    if (row == nil || row.unsignedIntegerValue >= self.material.stages.count) return;
    [self.stagesController setSelectionIndex:row.unsignedIntegerValue];
    [self.stagesTable scrollRowToVisible:row.integerValue];
    [self.view.window makeFirstResponder:self.stagesTable];
}

#pragma mark - The preview

/// The parse's stage that is the selected one in the text.
- (nullable UDMaterialStageInfo *)selectedStageInfo {
    NSUInteger selected = [self selectedStage];
    if (selected == NSNotFound) return nil;
    for (UDMaterialStageInfo *stage in self.parser.stages) {
        if (stage.textIndex == (NSInteger)selected) return stage;
    }
    return nil;
}

static NSImage *UDImageFromPixels(UDImage *image) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:image.width pixelsHigh:image.height
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:image.width * 4
                                                                  bitsPerPixel:32];
    memcpy(rep.bitmapData, image.pixels.bytes, (size_t)(image.width * image.height * 4));
    NSImage *result = [[NSImage alloc] initWithSize:NSMakeSize(image.width, image.height)];
    [result addRepresentation:rep];
    return result;
}

- (void)showPreview {
    if (self.parser == nil) [self reparse];
    UDMaterialStageInfo *stage = [self selectedStageInfo];
    NSString *label = @"";
    NSImage *image = nil;
    if ([self selectedStage] == NSNotFound) {
        label = @"";
    } else if (stage == nil) {
        label = @"The engine does not get to this stage.";
    } else if (stage.imageName.length == 0) {
        label = stage.cinematic ? @"A cinematic." : stage.dynamic ? @"A render of the view." : @"A program's.";
    } else if (stage.cubeMap != UDCubeFiles2D) {
        label = [NSString stringWithFormat:@"%@: a cube map.", stage.imageName];
    } else {
        NSString *problem = nil;
        UDImage *pixels = [UDImageProgram imageNamed:stage.imageName fileSystem:self.workspace.fileSystem problem:&problem];
        if (pixels != nil) {
            image = UDImageFromPixels(pixels);
            label = [NSString stringWithFormat:@"%@ (%d × %d)", stage.imageName, pixels.width, pixels.height];
        } else {
            label = problem ?: stage.imageName;
        }
    }
    self.previewView.image = image;
    self.previewLabel.stringValue = label;
}

@end
