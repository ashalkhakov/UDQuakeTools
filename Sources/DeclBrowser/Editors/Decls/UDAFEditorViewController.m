#import "UDAFEditorViewController.h"
#import "UDDeclManagedObjects.h"
#import "UDMD5Mesh.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"

static UDDiagnosticSource const UDAFReferencesSource = @"references";

@implementation UDAFEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDAFEditorView" bundle:[NSBundle bundleForClass:[UDAFEditorViewController class]]];
}

- (UDDeclAF *)figure {
    return (UDDeclAF *)self.declObject;
}

- (void)declDidLoad {
    if (self.figure.bodies.count > 0) {
        [self.bodiesController setSelectionIndex:0];
    }
    if (self.figure.constraints.count > 0) {
        [self.constraintsController setSelectionIndex:0];
    }
}

- (void)editingContextDidChange {
    [self checkReferences];
}

#pragma mark - Bodies and constraints

/// @a stem and the first number after it that no name in @a names is.
static NSString *UDUnusedName(NSString *stem, NSArray<NSString *> *names) {
    for (NSUInteger i = 1; ; i++) {
        NSString *name = [NSString stringWithFormat:@"%@%lu", stem, (unsigned long)i];
        BOOL used = NO;
        for (NSString *other in names) {
            if ([other caseInsensitiveCompare:name] == NSOrderedSame) {
                used = YES;
                break;
            }
        }
        if (!used) return name;
    }
}

static NSInteger UDSegment(id sender) {
    return [sender respondsToSelector:@selector(selectedSegment)] ? [sender selectedSegment] : 0;
}

- (IBAction)addOrRemoveBody:(id)sender {
    UDDeclAF *figure = self.figure;
    NSArray<UDAFBody *> *bodies = figure.bodies ?: @[];
    NSUInteger selected = self.bodiesController.selectionIndex;
    if (UDSegment(sender) == 0) {
        [figure ud_newBodyNamed:UDUnusedName(@"body", [bodies valueForKey:@"name"])];
        [self.bodiesController setSelectionIndex:figure.bodies.count - 1];
    } else if (selected != NSNotFound && selected < bodies.count) {
        [self moveSelectionOffRow:selected inController:self.bodiesController];
        [self.constraintsController setSelectionIndexes:[NSIndexSet indexSet]];
        [figure ud_deleteBodyNamed:bodies[selected].name];
        [self selectRowAfterRemovingRow:selected inController:self.bodiesController];
    } else {
        NSBeep();
    }
}

- (IBAction)addOrRemoveConstraint:(id)sender {
    UDDeclAF *figure = self.figure;
    NSArray<UDAFConstraint *> *constraints = figure.constraints ?: @[];
    NSUInteger selected = self.constraintsController.selectionIndex;
    if (UDSegment(sender) == 0) {
        [figure ud_newConstraintNamed:UDUnusedName(@"constraint", [constraints valueForKey:@"name"])];
        [self.constraintsController setSelectionIndex:figure.constraints.count - 1];
    } else if (selected != NSNotFound && selected < constraints.count) {
        [self moveSelectionOffRow:selected inController:self.constraintsController];
        [figure ud_deleteConstraintNamed:constraints[selected].name];
        [self selectRowAfterRemovingRow:selected inController:self.constraintsController];
    } else {
        NSBeep();
    }
}

#pragma mark - References

/// The bodies' names, as idPhysics_AF::GetBody finds one: by Icmp.
static BOOL UDHasName(NSArray<NSString *> *names, NSString *name) {
    for (NSString *other in names) {
        if ([other caseInsensitiveCompare:name] == NSOrderedSame) return YES;
    }
    return NO;
}

- (void)_addProblem:(NSString *)message severity:(UDDiagnosticSeverity)severity
               near:(nullable NSString *)text target:(nullable NSArray *)target to:(NSMutableArray<UDDiagnosticItem *> *)items {
    UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:text ?: @""] column:0
        message:message severity:severity source:UDAFReferencesSource];
    [items addObject:item];
    if (target != nil) [self setTarget:target forDiagnostic:item];
}

/// idAF::Load's checks, and AddBody's and LoadConstraint's lookups.
- (void)checkReferences {
    UDDeclAF *figure = self.figure;
    if (figure == nil || self.diagnosticStore == nil) return;
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    [self removeDiagnosticTargets];
    UDWorkspace *workspace = self.workspace;

    NSArray<UDAFBody *> *bodies = figure.bodies ?: @[];
    if (bodies.count == 0 || ![bodies[0].jointName isEqualToString:@"origin"]) {
        [self _addProblem:@"has no body which modifies the origin joint." severity:UDDiagnosticSeverityWarning
                     near:nil target:@[@"bodies"] to:items];
    }

    // The modelDef the figure is edited with; its mesh's joints.
    NSArray<NSString *> *joints = nil;
    NSString *model = figure.model ?: @"";
    if (model.length == 0 || [workspace.declManager findDeclWithoutParsing:DECL_MODELDEF name:model makeDefault:NO] == nil) {
        [self _addProblem:[NSString stringWithFormat:@"has no or defaulted modelDef '%@'", model] severity:UDDiagnosticSeverityWarning
                     near:(model.length > 0 ? model : nil) target:@[@"settings"] to:items];
    } else {
        joints = [UDMD5Mesh jointNamesOfModelDef:model declManager:workspace.declManager fileSystem:workspace.fileSystem];
        if (joints == nil) {
            NSString *mesh = [UDMD5Mesh meshOfModelDef:model declManager:workspace.declManager] ?: @"";
            [self _addProblem:[NSString stringWithFormat:@"has no or defaulted model '%@'", mesh] severity:UDDiagnosticSeverityWarning
                         near:model target:@[@"settings"] to:items];
        }
    }

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSUInteger row = 0; row < bodies.count; row++) {
        UDAFBody *body = bodies[row];
        [names addObject:body.name ?: @""];
        // idAnimator::GetJointHandle: by Icmp.
        if (joints != nil && !UDHasName(joints, body.jointName ?: @"")) {
            [self _addProblem:[NSString stringWithFormat:@"Body '%@' modifies unknown joint '%@'", body.name, body.jointName]
                     severity:UDDiagnosticSeverityError near:[NSString stringWithFormat:@"\"%@\"", body.name]
                       target:@[@"bodies", @(row)] to:items];
        }
    }

    NSArray<UDAFConstraint *> *constraints = figure.constraints ?: @[];
    for (NSUInteger row = 0; row < constraints.count; row++) {
        UDAFConstraint *constraint = constraints[row];
        NSString *near = [NSString stringWithFormat:@"\"%@\"", constraint.name];
        // GetBody gives NULL for a name no body has: no body 1, the world for body 2.
        if (!UDHasName(names, constraint.body1 ?: @"")) {
            [self _addProblem:[NSString stringWithFormat:@"Constraint '%@' has no body 1: no body '%@'", constraint.name, constraint.body1]
                     severity:UDDiagnosticSeverityError near:near target:@[@"constraints", @(row)] to:items];
        }
        if (!UDHasName(names, constraint.body2 ?: @"") && [constraint.body2 caseInsensitiveCompare:@"world"] != NSOrderedSame) {
            [self _addProblem:[NSString stringWithFormat:@"Constraint '%@' binds to the world: no body '%@'", constraint.name, constraint.body2]
                     severity:UDDiagnosticSeverityWarning near:near target:@[@"constraints", @(row)] to:items];
        }
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDAFReferencesSource];
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    NSArray *target = [self targetForDiagnostic:diagnostic];
    if (target == nil) return;
    [self.tabView selectTabViewItemWithIdentifier:target[0]];
    if (target.count < 2) return;
    NSUInteger row = [target[1] unsignedIntegerValue];
    BOOL isBody = [target[0] isEqualToString:@"bodies"];
    NSArrayController *controller = isBody ? self.bodiesController : self.constraintsController;
    NSTableView *table = isBody ? self.bodiesTable : self.constraintsTable;
    if (row >= [controller.arrangedObjects count]) return;
    [controller setSelectionIndex:row];
    [table scrollRowToVisible:(NSInteger)row];
    [self.view.window makeFirstResponder:table];
}

@end
