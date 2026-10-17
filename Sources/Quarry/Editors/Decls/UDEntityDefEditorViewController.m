#import "UDEntityDefEditorViewController.h"
#import "idDeclManager.h"
#import "UDDeclManagedObjects.h"

static UDDiagnosticSource const UDEntityDefReferencesSource = @"references";
static void *UDSelectionContext = &UDSelectionContext;

@interface UDEntityDefEditorViewController ()
@property (nonatomic, copy, readwrite) NSArray<UDInheritedKeyValue *> *inheritedKeyValues;
@property (nonatomic, copy, readwrite, nullable) NSString *usage;
@property (nonatomic, copy, readwrite, nullable) NSString *selectedKeyHelp;
@property (nonatomic, copy, nullable) NSString *selectedKey;
@property (nonatomic) BOOL observingSelections;
@property (nonatomic, readwrite) UDSpawnArgType selectedType;
@property (nonatomic) UDReferenceKind selectedKind;
@property (nonatomic) int selectedDeclType;
@property (nonatomic, copy) NSArray<UDEditorPane *> *panes;
@end

/// @a text, trimmed, is one number (an integer's, with @a integer).
static BOOL UDIsNumber(NSString *text, BOOL integer) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length == 0) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    if (integer) {
        long long whole = 0;
        return [scanner scanLongLong:&whole] && scanner.isAtEnd;
    }
    double number = 0;
    return [scanner scanDouble:&number] && scanner.isAtEnd;
}

/// @a value's numbers, split at spaces, when it is @a count of them.
static NSArray<NSString *> *UDNumbers(NSString *value, NSUInteger count) {
    NSMutableArray<NSString *> *numbers = [NSMutableArray array];
    for (NSString *part in [value componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (part.length == 0) continue;
        if (!UDIsNumber(part, NO)) return nil;
        [numbers addObject:part];
    }
    return numbers.count == count ? numbers : nil;
}

/// A colour's channel as the retail defs write them: no more digits than
/// it needs, up to four.
static NSString *UDChannelText(CGFloat channel) {
    NSString *text = [NSString stringWithFormat:@"%.4f", (double)channel];
    while ([text hasSuffix:@"0"]) text = [text substringToIndex:text.length - 1];
    if ([text hasSuffix:@"."]) text = [text substringToIndex:text.length - 1];
    return [text isEqualToString:@"-0"] ? @"0" : text;
}

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
    [self _updateInspector];
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
    }    if (controller == self.keyValuesController) [self _updateInspector];
}

- (void)_updateHelp {
    NSString *key = self.selectedKey;
    NSString *help = key.length > 0 ? [self.entityDef ud_helpForKey:key] : nil;
    self.selectedKeyHelp = help != nil ? [NSString stringWithFormat:@"%@: %@", key, help] : nil;
}

#pragma mark - The inspector

- (NSArray<UDEditorPane *> *)inspectorPanes {
    if (self.panes == nil && self.inspectorView != nil) {
        self.panes = @[[UDEditorPane paneWithTitle:@"Properties" letters:@"P" red:0.62 green:0.42 blue:0.68 view:self.inspectorView]];
    }
    return self.panes ?: @[];
}

+ (UDSpawnArgType)typeOfKey:(NSString *)key value:(NSString *)value editorType:(NSString *)editorType
                       kind:(UDReferenceKind *)kind declType:(int *)declType {
    UDReferenceKind referenceKind = UDReferenceDecls;
    int referenceType = -1;
    UDSpawnArgType type = UDSpawnArgText;
    NSString *lower = key.lowercaseString;
    // Radiant's: the editor_* key's
    if ([editorType isEqualToString:@"bool"]) type = UDSpawnArgBool;
    else if ([editorType isEqualToString:@"color"]) type = UDSpawnArgColor;
    else if ([editorType isEqualToString:@"int"]) type = UDSpawnArgInteger;
    else if ([editorType isEqualToString:@"float"]) type = UDSpawnArgNumber;
    else if ([editorType isEqualToString:@"mat"]) referenceKind = UDReferenceMaterials;
    else if ([editorType isEqualToString:@"model"]) referenceKind = UDReferenceEntityModels;
    else if ([editorType isEqualToString:@"gui"]) referenceKind = UDReferenceGuis;
    else if ([editorType isEqualToString:@"snd"]) referenceType = DECL_SOUND;
    // the key's name
    else if ([lower hasSuffix:@"color"] && (value.length == 0 || UDNumbers(value, 3) != nil)) type = UDSpawnArgColor;
    else if ([lower hasPrefix:@"snd_"]) referenceType = DECL_SOUND;
    else if ([lower isEqualToString:@"model"] || [lower hasPrefix:@"model_"]) referenceKind = UDReferenceEntityModels;
    else if ([lower hasPrefix:@"def_"]) referenceType = DECL_ENTITYDEF;
    else if ([lower hasPrefix:@"mtr_"] || [lower isEqualToString:@"material"]) referenceKind = UDReferenceMaterials;
    else if ([lower isEqualToString:@"skin"] || [lower hasPrefix:@"skin_"]) referenceType = DECL_SKIN;
    else if ([lower isEqualToString:@"articulatedfigure"] || [lower isEqualToString:@"ragdoll"]) referenceType = DECL_AF;
    else if ([lower isEqualToString:@"gui"] || ([lower hasPrefix:@"gui"] && lower.length > 3
             && [[lower substringFromIndex:3] rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound)) {
        referenceKind = UDReferenceGuis;
    }
    else if ([lower isEqualToString:@"fx"] || [lower hasPrefix:@"fx_"]) referenceType = DECL_FX;
    else if ([lower hasPrefix:@"smoke_"]) referenceType = DECL_PARTICLE;
    // what the value looks like
    else if (UDNumbers(value, 3) != nil) type = UDSpawnArgVector;
    else if (UDIsNumber(value ?: @"", NO)) type = UDSpawnArgNumber;

    if (type == UDSpawnArgText && (referenceKind != UDReferenceDecls || referenceType >= 0)) type = UDSpawnArgReference;
    if (kind != NULL) *kind = referenceKind;
    if (declType != NULL) *declType = referenceType;
    return type;
}

/// What the type's entry is, in words.
- (NSString *)_describeType:(UDSpawnArgType)type editorType:(NSString *)editorType {
    NSString *what = @"Text";
    switch (type) {
        case UDSpawnArgText: break;
        case UDSpawnArgNumber: what = @"A number"; break;
        case UDSpawnArgInteger: what = @"A whole number"; break;
        case UDSpawnArgVector: what = @"A vector: x y z"; break;
        case UDSpawnArgBool: what = @"On (1) or off (0)"; break;
        case UDSpawnArgColor: what = @"A colour: red green blue, 0 to 1"; break;
        case UDSpawnArgReference:
            switch (self.selectedKind) {
                case UDReferenceMaterials: what = @"A material"; break;
                case UDReferenceEntityModels: what = @"A modelDef or a model file"; break;
                case UDReferenceGuis: what = @"A GUI"; break;
                default:
                    switch (self.selectedDeclType) {
                        case DECL_SOUND: what = @"A sound shader"; break;
                        case DECL_ENTITYDEF: what = @"An entityDef"; break;
                        case DECL_SKIN: what = @"A skin"; break;
                        case DECL_AF: what = @"An articulated figure"; break;
                        case DECL_FX: what = @"An FX"; break;
                        case DECL_PARTICLE: what = @"A particle system"; break;
                        default: break;
                    }
            }
            break;
    }
    return editorType.length > 0 && ![editorType isEqualToString:@"var"]
        ? [NSString stringWithFormat:@"%@ (editor_%@)", what, editorType] : what;
}

/// The selected pair, its type, and its value in the type's entry.
- (void)_updateInspector {
    if (self.valuePages == nil) return;
    UDEntityKeyValue *pair = self.keyValuesController.selectedObjects.firstObject;
    if (pair == nil) {
        self.keyLabel.stringValue = @"";
        self.kindLabel.stringValue = @"";
        [self.valuePages selectTabViewItemWithIdentifier:@"none"];
        return;
    }
    NSString *editorType = [self.entityDef ud_editorTypeForKey:pair.key];
    UDReferenceKind kind = UDReferenceDecls;
    int declType = -1;
    self.selectedType = [[self class] typeOfKey:pair.key value:pair.value editorType:editorType kind:&kind declType:&declType];
    self.selectedKind = kind;
    self.selectedDeclType = declType;
    self.keyLabel.stringValue = pair.key ?: @"";
    self.kindLabel.stringValue = [self _describeType:self.selectedType editorType:editorType];
    NSString *value = pair.value ?: @"";
    NSString *page = @"text";
    switch (self.selectedType) {
        case UDSpawnArgText: break;
        case UDSpawnArgReference: page = @"reference"; break;
        case UDSpawnArgNumber:
        case UDSpawnArgInteger:
            page = @"number";
            self.numberField.stringValue = value;
            break;
        case UDSpawnArgVector: {
            page = @"vector";
            NSArray<NSString *> *xyz = UDNumbers(value, 3) ?: @[@"0", @"0", @"0"];
            self.vectorXField.stringValue = xyz[0];
            self.vectorYField.stringValue = xyz[1];
            self.vectorZField.stringValue = xyz[2];
            break;
        }
        case UDSpawnArgBool:
            page = @"bool";
            self.boolCheckbox.state = atoi(value.UTF8String) != 0 ? NSControlStateValueOn : NSControlStateValueOff;
            break;
        case UDSpawnArgColor: {
            page = @"color";
            NSArray<NSString *> *rgb = UDNumbers(value, 3) ?: @[@"1", @"1", @"1"];
            self.colorWell.color = [NSColor colorWithCalibratedRed:rgb[0].doubleValue green:rgb[1].doubleValue
                                                              blue:rgb[2].doubleValue alpha:1];
            break;
        }
    }
    [self.valuePages selectTabViewItemWithIdentifier:page];
}

- (IBAction)valueEdited:(id)sender {
    UDEntityKeyValue *pair = self.keyValuesController.selectedObjects.firstObject;
    if (pair == nil) return;
    NSString *value = nil;
    if (sender == self.boolCheckbox) {
        value = self.boolCheckbox.state == NSControlStateValueOn ? @"1" : @"0";
    } else if (sender == self.colorWell) {
        NSColor *color = [self.colorWell.color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        NSArray<NSString *> *old = UDNumbers(pair.value ?: @"", 3);
        // the value as it was while the well still shows it
        if (old != nil && fabs(old[0].doubleValue - color.redComponent) < 1e-4 && fabs(old[1].doubleValue - color.greenComponent) < 1e-4
            && fabs(old[2].doubleValue - color.blueComponent) < 1e-4) {
            return;
        }
        value = [NSString stringWithFormat:@"%@ %@ %@", UDChannelText(color.redComponent), UDChannelText(color.greenComponent),
                 UDChannelText(color.blueComponent)];
    } else if (sender == self.numberField) {
        value = [self.numberField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!UDIsNumber(value, self.selectedType == UDSpawnArgInteger)) value = nil;
    } else if (sender == self.vectorXField || sender == self.vectorYField || sender == self.vectorZField) {
        NSMutableArray<NSString *> *xyz = [NSMutableArray array];
        for (NSTextField *field in @[self.vectorXField, self.vectorYField, self.vectorZField]) {
            NSString *number = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!UDIsNumber(number, NO)) {
                xyz = nil;
                break;
            }
            [xyz addObject:number];
        }
        value = xyz != nil ? [xyz componentsJoinedByString:@" "] : nil;
    }
    if (value == nil) {
        // not a number: what it was
        NSBeep();
        [self _updateInspector];
        return;
    }
    if (![value isEqualToString:pair.value ?: @""]) pair.value = value;
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

#pragma mark - Pickers

/// The entityDef it inherits; the selected pair's value (its type's).
- (UDReferenceField *)referenceFieldForTag:(NSInteger)tag {
    if (tag == 2) {
        UDEntityKeyValue *pair = self.keyValuesController.selectedObjects.firstObject;
        if (pair == nil || self.selectedType != UDSpawnArgReference) return nil;
        UDReferenceField *field = [UDReferenceField fieldTitled:[NSString stringWithFormat:@"%@: %@", pair.key,
                                                                 [self _describeType:self.selectedType editorType:nil]]
                                                            key:@"value" controller:self.keyValuesController kind:self.selectedKind];
        field.declType = self.selectedDeclType;
        return field;
    }
    if (tag != 1) return nil;
    UDReferenceField *field = [UDReferenceField fieldTitled:@"The entityDef it inherits" key:@"inherit" controller:self.objectController kind:UDReferenceDecls];
    field.declType = DECL_ENTITYDEF;
    return field;
}

@end
