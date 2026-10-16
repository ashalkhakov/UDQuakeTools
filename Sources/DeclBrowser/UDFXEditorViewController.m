#import "UDFXEditorViewController.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "idFileSystem.h"
#import "UDFXTimelineView.h"
#import "UDParticlePreview.h"

static UDDiagnosticSource const UDFXReferencesSource = @"references";

@interface UDFXEditorViewController ()
@property (nonatomic, strong, readwrite, nullable) UDParticlePreview *preview;
@end

@implementation UDFXEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDFXEditorView" bundle:[NSBundle bundleForClass:[UDFXEditorViewController class]]];
}

- (UDDeclFX *)fx {
    return (UDDeclFX *)self.declObject;
}

- (void)declDidLoad {
    if (self.fx.actions.count > 0) {
        [self.actionsController setSelectionIndex:0];
    }
    if (self.previewView != nil) {
        self.preview = [[UDParticlePreview alloc] initWithImageView:self.previewView workspace:self.workspace];
        self.preview.target = self;
        self.preview.action = @selector(previewDidDraw:);
    }
}

- (void)editingContextDidChange {
    [self checkReferences];
    self.preview.fxActions = self.fx.actions;
    self.timelineView.actions = self.fx.actions;
    self.timelineView.duration = self.preview.fxDuration;
}

- (IBAction)restartPreview:(id)sender {
    [self.preview restart];
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
}

@end
