#import "UDEntityDefEditorViewController.h"
#import "UDDeclManagedObjects.h"

static UDDiagnosticSource const UDEntityDefReferencesSource = @"references";
static void *UDSelectionContext = &UDSelectionContext;

@interface UDEntityDefEditorViewController ()
@property (nonatomic, copy, readwrite) NSArray<UDInheritedKeyValue *> *inheritedKeyValues;
@property (nonatomic, copy, readwrite, nullable) NSString *usage;
@property (nonatomic, copy, readwrite, nullable) NSString *selectedKeyHelp;
@property (nonatomic, copy, nullable) NSString *selectedKey;
@property (nonatomic) BOOL observingSelections;
@end

@implementation UDEntityDefEditorViewController

- (instancetype)init {
    self = [super initWithNibName:@"UDEntityDefEditorView" bundle:[NSBundle bundleForClass:[UDEntityDefEditorViewController class]]];
    if (self) {
        _inheritedKeyValues = @[];
    }
    return self;
}

- (void)dealloc {
    if (self.observingSelections) {
        [self.keyValuesController removeObserver:self forKeyPath:@"selectionIndexes" context:UDSelectionContext];
        [self.inheritedController removeObserver:self forKeyPath:@"selectionIndexes" context:UDSelectionContext];
    }
}

- (UDDeclEntityDef *)entityDef {
    return (UDDeclEntityDef *)self.declObject;
}

- (void)declDidLoad {
    // The inherit pair has its field (DialogEntityDefEditor took it out of
    // the list too).
    self.keyValuesController.filterPredicate = [NSPredicate predicateWithFormat:@"key !=[c] %@", @"inherit"];
    [self.keyValuesController rearrangeObjects];      // GNUstep's setter does not
    [self.keyValuesController addObserver:self forKeyPath:@"selectionIndexes" options:0 context:UDSelectionContext];
    [self.inheritedController addObserver:self forKeyPath:@"selectionIndexes" options:0 context:UDSelectionContext];
    self.observingSelections = YES;
}

- (void)editingContextDidChange {
    UDDeclEntityDef *entityDef = self.entityDef;
    if (entityDef == nil) return;
    NSArray<NSString *> *unknown = nil;
    self.inheritedKeyValues = [entityDef ud_inheritedKeyValuesUnknown:&unknown];
    self.usage = [entityDef ud_usage];
    [self _updateHelp];
    [self _checkPairs:unknown];
}

#pragma mark - The selected key's help

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != UDSelectionContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    // The help follows the selection last made, in either list.
    NSArrayController *controller = object;
    NSArray *selected = controller.selectedObjects;
    if (selected.count > 0) {
        self.selectedKey = [selected.firstObject valueForKey:@"key"];
        [self _updateHelp];
    }
}

- (void)_updateHelp {
    NSString *key = self.selectedKey;
    NSString *help = key.length > 0 ? [self.entityDef ud_helpForKey:key] : nil;
    self.selectedKeyHelp = help != nil ? [NSString stringWithFormat:@"%@: %@", key, help] : nil;
}

#pragma mark - The lists

/// The decl's index of the list's selected pair (the list leaves inherit
/// out), or NSNotFound.
- (NSUInteger)_selectedIndex {
    UDEntityKeyValue *selected = self.keyValuesController.selectedObjects.firstObject;
    return selected != nil ? [self.entityDef.keyValues indexOfObjectIdenticalTo:selected] : NSNotFound;
}

/// A key the decl does not set: @a base, or base2, base3...
- (NSString *)_unusedKey:(NSString *)base {
    NSSet *keys = [NSSet setWithArray:[[self.entityDef.keyValues valueForKey:@"key"] valueForKey:@"lowercaseString"]];
    NSString *key = base;
    for (NSUInteger n = 2; [keys containsObject:key.lowercaseString]; n++) {
        key = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)n];
    }
    return key;
}

- (void)_insertPair:(UDEntityKeyValue *)pair editColumn:(NSString *)column {
    NSMutableArray *pairs = [self.entityDef.keyValues mutableCopy] ?: [NSMutableArray array];
    NSUInteger selected = [self _selectedIndex];
    NSUInteger at = selected != NSNotFound ? selected + 1 : pairs.count;
    [pairs insertObject:pair atIndex:at];
    self.entityDef.keyValues = pairs;
    UDEntityKeyValue *inserted = self.entityDef.keyValues[at];
    [self.keyValuesController setSelectedObjects:@[inserted]];
    NSUInteger row = self.keyValuesController.selectionIndex;
    if (row != NSNotFound) {
        [self.keyValuesTable editColumn:[self.keyValuesTable columnWithIdentifier:column] row:(NSInteger)row withEvent:nil select:YES];
    }
}

- (IBAction)addOrRemovePair:(id)sender {
    NSInteger segment = [sender respondsToSelector:@selector(selectedSegment)] ? [sender selectedSegment] : 0;
    if (segment == 0) {
        [self _insertPair:[UDEntityKeyValue keyValueWithKey:[self _unusedKey:@"key"] value:@""] editColumn:@"key"];
        return;
    }
    NSUInteger selected = [self _selectedIndex];
    if (selected == NSNotFound) {
        NSBeep();
        return;
    }
    NSUInteger row = self.keyValuesController.selectionIndex;
    [self moveSelectionOffRow:row inController:self.keyValuesController];
    NSMutableArray *pairs = [self.entityDef.keyValues mutableCopy];
    [pairs removeObjectAtIndex:selected];
    self.entityDef.keyValues = pairs;
    [self selectRowAfterRemovingRow:row inController:self.keyValuesController];
}

- (IBAction)overrideInherited:(id)sender {
    UDInheritedKeyValue *inherited = self.inheritedController.selectedObjects.firstObject;
    if (inherited == nil) {
        NSBeep();
        return;
    }
    [self _insertPair:[UDEntityKeyValue keyValueWithKey:inherited.key value:inherited.value] editColumn:@"value"];
}

#pragma mark - Issues

- (void)_checkPairs:(NSArray<NSString *> *)unknown {
    if (self.diagnosticStore == nil) return;
    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    [self removeDiagnosticTargets];

    // idDeclEntityDef::Parse's warnings.
    for (NSString *name in unknown) {
        UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:name] column:0
            message:[NSString stringWithFormat:@"Unknown entityDef '%@' inherited by '%@'", name, self.entityDef.name]
            severity:UDDiagnosticSeverityWarning source:UDEntityDefReferencesSource];
        [items addObject:item];
        [self setTarget:@"inherit" forDiagnostic:item];
    }
    NSArray<UDEntityKeyValue *> *pairs = self.entityDef.keyValues;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (UDEntityKeyValue *pair in pairs) {
        NSString *lower = pair.key.lowercaseString ?: @"";
        if (![seen containsObject:lower]) {
            [seen addObject:lower];
            continue;
        }
        UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self lineOfDeclTextContaining:[NSString stringWithFormat:@"\"%@\"", pair.key]] column:0
            message:[NSString stringWithFormat:@"'%@' already defined", pair.key]
            severity:UDDiagnosticSeverityWarning source:UDEntityDefReferencesSource];
        [items addObject:item];
        [self setTarget:pair forDiagnostic:item];
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDEntityDefReferencesSource];
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    id target = [self targetForDiagnostic:diagnostic];
    if ([target isEqual:@"inherit"]) {
        NSView *field = [self _viewWithToolTip:@"inherit" in:self.view];
        [field.window makeFirstResponder:field];
        return;
    }
    // The pair with that key, the second of its kind.
    UDEntityKeyValue *pair = target;
    NSArray *same = [self.keyValuesController.arrangedObjects filteredArrayUsingPredicate:
                     [NSPredicate predicateWithFormat:@"key ==[c] %@", pair.key ?: @""]];
    if (same.count == 0) return;
    [self.keyValuesController setSelectedObjects:@[same.lastObject]];
    [self.keyValuesTable scrollRowToVisible:(NSInteger)self.keyValuesController.selectionIndex];
    [self.view.window makeFirstResponder:self.keyValuesTable];
}

- (NSView *)_viewWithToolTip:(NSString *)toolTip in:(NSView *)view {
    if ([view.toolTip isEqualToString:toolTip]) return view;
    for (NSView *subview in view.subviews) {
        NSView *found = [self _viewWithToolTip:toolTip in:subview];
        if (found != nil) return found;
    }
    return nil;
}

@end
