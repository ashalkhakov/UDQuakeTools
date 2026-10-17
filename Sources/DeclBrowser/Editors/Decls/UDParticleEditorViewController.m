#import "UDParticleEditorViewController.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspace.h"
#import "UDParticlePreview.h"
#import "UDTransportController.h"
#import "idDeclManager.h"

static UDDiagnosticSource const UDParticleReferencesSource = @"references";

@interface UDParticleEditorViewController ()
@property (nonatomic, strong, readwrite, nullable) UDTransportController *transport;
@property (nonatomic, strong, readwrite, nullable) UDParticlePreview *preview;
@end

@implementation UDParticleEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDParticleEditorView" bundle:[NSBundle bundleForClass:[UDParticleEditorViewController class]]];
}

- (UDDeclParticle *)particle {
    return (UDDeclParticle *)self.declObject;
}

- (void)declDidLoad {
    if (self.particle.stages.count > 0) {
        [self.stagesController setSelectionIndex:0];
    }
    if (self.previewView != nil) {
        self.preview = [[UDParticlePreview alloc] initWithImageView:self.previewView workspace:self.workspace];
        self.transport = [[UDTransportController alloc] init];
        self.transport.playable = self.preview;
        self.preview.transport = self.transport;
        [self.transport installInView:self.transportView];
    }
}

- (void)editingContextDidChange {
    [self checkReferences];
    self.preview.stages = self.particle.stages;
}

#pragma mark - The stages (AddStage, RemoveStage)

- (IBAction)addOrRemoveStage:(id)sender {
    NSInteger segment = [sender respondsToSelector:@selector(selectedSegment)] ? [sender selectedSegment] : 0;
    NSMutableArray<UDParticleStage *> *stages = [self.particle.stages mutableCopy] ?: [NSMutableArray array];
    NSUInteger selected = self.stagesController.selectionIndex;
    if (segment == 0) {
        UDParticleStage *source = selected != NSNotFound && selected < stages.count ? stages[selected] : nil;
        BOOL copying = ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
        if (copying && source == nil) {
            NSBeep();
            return;
        }
        UDParticleStage *stage = copying ? [source copy] : [[UDParticleStage alloc] init];   // Default()
        NSUInteger at = selected != NSNotFound && selected < stages.count ? selected + 1 : stages.count;
        [stages insertObject:stage atIndex:at];
        self.particle.stages = stages;
        [self.stagesController setSelectionIndex:at];
    } else if (selected != NSNotFound && selected < stages.count) {
        [self moveSelectionOffRow:selected inController:self.stagesController];
        [stages removeObjectAtIndex:selected];
        self.particle.stages = stages;
        [self selectRowAfterRemovingRow:selected inController:self.stagesController];
    } else {
        NSBeep();
    }
}

#pragma mark - The stage list's numbers

// Its rows are its array controller's (the content binding); the Stage
// column, unbound, is "stage <row>", as DialogParticleEditor listed them.
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[self.stagesController.arrangedObjects count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return [tableColumn.identifier isEqualToString:@"stage"] ? [NSString stringWithFormat:@"stage %ld", (long)row] : nil;
}

#pragma mark - References

- (void)checkReferences {
    UDDeclParticle *particle = self.particle;
    if (particle == nil || self.diagnosticStore == nil) return;
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    [self removeDiagnosticTargets];

    NSArray<UDParticleStage *> *stages = particle.stages;
    for (NSUInteger row = 0; row < stages.count; row++) {
        UDParticleStage *stage = stages[row];
        NSString *material = stage.material ?: @"";
        if (![self materialExists:material]) {
            UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:material] column:0
                message:[NSString stringWithFormat:@"Stage %lu: material “%@” is neither a decl nor an image: the engine makes it a default material",
                         (unsigned long)row, material]
                severity:UDDiagnosticSeverityWarning source:UDParticleReferencesSource];
            [items addObject:item];
            [self setTarget:@(row) forDiagnostic:item];
        }
        // ParseParametric's FindType( DECL_TABLE, token, false ): no table, from and to 0.
        for (NSString *prefix in @[@"speed", @"rotation", @"size", @"aspect"]) {
            NSString *table = [stage valueForKey:[prefix stringByAppendingString:@"Table"]];
            if (table.length == 0 ||
                [self.workspace.declManager findDeclWithoutParsing:DECL_TABLE name:table makeDefault:NO] != nil) continue;
            UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:table] column:0
                message:[NSString stringWithFormat:@"Stage %lu: no table “%@” for its %@: the engine takes it as 0",
                         (unsigned long)row, table, prefix]
                severity:UDDiagnosticSeverityWarning source:UDParticleReferencesSource];
            [items addObject:item];
            [self setTarget:@(row) forDiagnostic:item];
        }
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDParticleReferencesSource];
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    NSNumber *row = [self targetForDiagnostic:diagnostic];
    if (row == nil || row.unsignedIntegerValue >= self.particle.stages.count) return;
    [self.stagesController setSelectionIndex:row.unsignedIntegerValue];
    [self.stagesTable scrollRowToVisible:row.integerValue];
    [self.view.window makeFirstResponder:self.stagesTable];
}

@end
