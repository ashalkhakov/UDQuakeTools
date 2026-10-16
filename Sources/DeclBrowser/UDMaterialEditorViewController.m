#import "UDMaterialEditorViewController.h"
#import "UDDeclManagedObjects.h"
#import "UDDeclTextChecker.h"
#import "UDImageProgram.h"
#import "UDMaterialParser.h"
#import "UDWorkspace.h"

static UDDiagnosticSource const UDMaterialParseSource = @"parse";
static UDDiagnosticSource const UDMaterialImagesSource = @"references";

@interface UDMaterialEditorViewController ()
/// idMaterial::Parse of the text as it is now.
@property (nonatomic, strong, nullable) UDMaterialParser *parser;
@property (nonatomic) BOOL observingSelection;
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
}

- (void)dealloc {
    if (_observingSelection) [_stagesController removeObserver:self forKeyPath:@"selectionIndexes"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == self.stagesController) {
        [self showPreview];
    }
}

- (void)declDidLoad {
    if (self.material.stages.count > 0) {
        [self.stagesController setSelectionIndex:0];
    }
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

#pragma mark - What the engine says

- (void)reparse {
    UDDeclMaterial *material = self.material;
    if (material == nil || self.diagnosticStore == nil) return;
    NSData *data = [material ud_currentText:NULL];
    NSString *text = data != nil ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (text == nil) return;
    self.parser = [[UDMaterialParser alloc] initWithText:text name:material.name declManager:self.workspace.declManager];

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
    [self.tabView selectTabViewItemWithIdentifier:@"stages"];
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
