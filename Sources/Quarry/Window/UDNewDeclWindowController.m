#import "UDNewDeclWindowController.h"
#import "idDeclManager.h"

@implementation UDNewDeclWindowController {
    idDeclManager *_declManager;
    BOOL _fileNameTyped;          // the file is the user's, not the default
}

- (instancetype)initWithDeclManager:(idDeclManager *)declManager typeName:(NSString *)typeName {
    self = [super initWithWindowNibName:@"UDNewDecl"];
    if (self) {
        _declManager = declManager;
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (int i = 0; i < [declManager numDeclTypes]; i++) {
            NSString *name = [declManager declNameFromType:(declType_t)i];
            if (name.length > 0 && ![name isEqualToString:@"bad type"]) [names addObject:name];
        }
        _typeNames = [names copy];
        _typeName = [names containsObject:typeName] ? [typeName copy] : names.firstObject ?: @"";
        _declName = @"";
        _fileName = [[self class] defaultFileNameForTypeName:_typeName name:@"" declManager:declManager];
    }
    return self;
}

// DialogDeclNew::OnBnClickedFile's folders, for the types no folder of the
// game's is registered for; the ones that are go where the decl manager
// reads them. Its last resort is def/*.decl, which Doom 3 never reads:
// def/*.def it is.
+ (NSString *)defaultFileNameForTypeName:(NSString *)typeName name:(NSString *)name declManager:(idDeclManager *)declManager {
    declType_t type = [declManager declTypeFromName:typeName];
    NSString *fileName = name.length > 0 ? name : @"<name>";
    NSString *registered = [declManager defaultFileNameForDeclType:type name:fileName];
    if (registered.length > 0) return registered;
    switch (type) {
        case DECL_TABLE:    return [NSString stringWithFormat:@"materials/%@.mtr", fileName];
        default:            return [NSString stringWithFormat:@"def/%@.def", fileName];
    }
}

- (void)_updateDefaultFileName {
    if (_fileNameTyped) return;
    [self willChangeValueForKey:@"fileName"];
    _fileName = [[self class] defaultFileNameForTypeName:self.typeName name:self.declName declManager:_declManager];
    [self didChangeValueForKey:@"fileName"];
}

- (void)setTypeName:(NSString *)typeName {
    _typeName = [typeName copy];
    [self _updateDefaultFileName];
}

- (void)setDeclName:(NSString *)declName {
    _declName = [declName copy];
    [self _updateDefaultFileName];
}

- (void)setFileName:(NSString *)fileName {
    _fileName = [fileName copy];
    _fileNameTyped = YES;
}

- (NSModalResponse)runModal {
    [self.window center];
    return [NSApp runModalForWindow:self.window];
}

#pragma mark - Create / Cancel (DialogDeclNew::OnBnClickedOk)

- (IBAction)create:(id)sender {
    // What is being typed goes into its property first.
    if (![self.window makeFirstResponder:nil]) {
        [self.window endEditingFor:nil];
    }
    NSString *name = [self.declName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *file = [self.fileName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    declType_t type = [_declManager declTypeFromName:self.typeName];

    NSString *problem = nil;
    if (type == DECL_MAX_TYPES) {
        problem = @"No declaration type selected.";
    } else if (name.length == 0) {
        problem = @"No declaration name specified.";
    } else if (file.length == 0 || [file containsString:@"<name>"]) {
        problem = @"No file name specified.";
    } else if ([_declManager findDeclWithoutParsing:type name:name makeDefault:NO] != nil) {
        problem = @"Declaration already exists.";
    }
    if (problem != nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Error creating declaration.";
        alert.informativeText = problem;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    _declName = [name copy];
    _fileName = [file copy];
    [NSApp stopModalWithCode:NSModalResponseOK];
    [self.window orderOut:nil];
}

- (IBAction)cancel:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseCancel];
    [self.window orderOut:nil];
}

@end
