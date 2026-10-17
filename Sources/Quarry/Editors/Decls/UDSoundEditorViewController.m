#import "UDSoundEditorViewController.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "idFileSystem.h"

static UDDiagnosticSource const UDSoundReferencesSource = @"references";

@implementation UDSoundEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDSoundEditorView" bundle:[NSBundle bundleForClass:[UDSoundEditorViewController class]]];
}

- (UDDeclSound *)sound {
    return (UDDeclSound *)self.declObject;
}

- (void)editingContextDidChange {
    [self checkReferences];
}

#pragma mark - The lists

/// A sample added after the selection of @a controller (at the end without
/// one), its path to be typed; or the selection taken off.
- (void)_addOrRemove:(NSInteger)segment key:(NSString *)key controller:(NSArrayController *)controller
               table:(NSTableView *)table {
    NSMutableArray *samples = [[self.sound valueForKey:key] mutableCopy] ?: [NSMutableArray array];
    NSUInteger selected = controller.selectionIndex;
    if (segment == 0) {
        NSUInteger at = selected != NSNotFound && selected < samples.count ? selected + 1 : samples.count;
        [samples insertObject:[UDSoundSample sampleWithPath:@"sound/"] atIndex:at];
        [self.sound setValue:samples forKey:key];
        [controller setSelectionIndex:at];
        [table editColumn:0 row:(NSInteger)at withEvent:nil select:YES];
    } else if (selected != NSNotFound && selected < samples.count) {
        [self moveSelectionOffRow:selected inController:controller];
        [samples removeObjectAtIndex:selected];
        [self.sound setValue:samples forKey:key];
        [self selectRowAfterRemovingRow:selected inController:controller];
    } else {
        NSBeep();
    }
}

- (IBAction)addOrRemoveSample:(NSSegmentedControl *)sender {
    [self _addOrRemove:sender.selectedSegment key:@"samples" controller:self.samplesController table:self.samplesTable];
}

- (IBAction)addOrRemoveLeadin:(NSSegmentedControl *)sender {
    [self _addOrRemove:sender.selectedSegment key:@"leadins" controller:self.leadinsController table:self.leadinsTable];
}

#pragma mark - References

/// idSoundSample::GetNewTimeStamp: the sample, or the .ogg of its name.
- (BOOL)_sampleExists:(NSString *)path {
    idFileSystem *fileSystem = self.workspace.fileSystem;
    if (path.pathExtension.length > 0 && [fileSystem readFile:path buffer:NULL timestamp:NULL error:NULL] >= 0) return YES;
    NSString *ogg = [path.stringByDeletingPathExtension stringByAppendingPathExtension:@"ogg"];
    return [fileSystem readFile:ogg buffer:NULL timestamp:NULL error:NULL] >= 0;
}

- (void)_checkSamples:(NSArray<UDSoundSample *> *)samples controller:(NSArrayController *)controller
                 into:(NSMutableArray<UDDiagnosticItem *> *)items {
    for (NSUInteger row = 0; row < samples.count; row++) {
        NSString *path = samples[row].path ?: @"";
        if ([self _sampleExists:path]) continue;
        // idSoundSample::Load's MakeDefault.
        UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:path] column:0
            message:[NSString stringWithFormat:@"Couldn't load sound '%@' using default", path]
            severity:UDDiagnosticSeverityWarning source:UDSoundReferencesSource];
        [items addObject:item];
        [self setTarget:@[controller, @(row)] forDiagnostic:item];
    }
}

- (void)checkReferences {
    UDDeclSound *sound = self.sound;
    if (sound == nil || self.diagnosticStore == nil) return;
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    [self removeDiagnosticTargets];

    [self _checkSamples:sound.samples controller:self.samplesController into:items];
    [self _checkSamples:sound.leadins controller:self.leadinsController into:items];
    // SOUND_MAX_LIST_WAVS: ParseShader keeps no more.
    if (sound.samples.count > 32) {
        [items addObject:[[UDDiagnosticItem alloc] initWithLine:1 column:0
            message:[NSString stringWithFormat:@"%lu samples: the engine plays the first 32", (unsigned long)sound.samples.count]
            severity:UDDiagnosticSeverityWarning source:UDSoundReferencesSource]];
    }
    // FindSound makes a shader of a name no decl defines: its .wav.
    NSString *alt = sound.altSound;
    if (alt.length > 0 && [self.workspace.declManager findDeclWithoutParsing:DECL_SOUND name:alt makeDefault:NO] == nil) {
        UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:alt] column:0
            message:[NSString stringWithFormat:@"No sound shader '%@': the engine makes one of %@.wav", alt, alt]
            severity:UDDiagnosticSeverityWarning source:UDSoundReferencesSource];
        [items addObject:item];
        [self setTarget:@"altSound" forDiagnostic:item];
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDSoundReferencesSource];
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    id target = [self targetForDiagnostic:diagnostic];
    if (![target isKindOfClass:[NSArray class]]) return;
    NSArrayController *controller = target[0];
    NSUInteger index = [target[1] unsignedIntegerValue];
    if (index >= [[controller arrangedObjects] count]) return;
    [controller setSelectionIndex:index];
    NSTableView *table = controller == self.samplesController ? self.samplesTable : self.leadinsTable;
    [table scrollRowToVisible:(NSInteger)index];
    [table.window makeFirstResponder:table];
}

@end
