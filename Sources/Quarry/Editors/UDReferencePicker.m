/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDReferencePicker.m
 */

#import "UDReferencePicker.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "idFileSystem.h"

@interface UDReferencePicker () <NSTextFieldDelegate>
@property (nonatomic, copy) NSString *pickerTitle;
@property (nonatomic, copy) NSArray<NSString *> *names;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *details;
@property (nonatomic, copy, nullable) NSString *current;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *shownNames;
@property (nonatomic, copy, readwrite, nullable) NSString *chosenName;
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
@end

@implementation UDReferenceField

+ (instancetype)fieldTitled:(NSString *)title key:(NSString *)key controller:(id)controller kind:(UDReferenceKind)kind {
    UDReferenceField *field = [[UDReferenceField alloc] init];
    field.title = title;
    field.key = key;
    field.controller = controller;
    field.kind = kind;
    return field;
}

@end

@implementation UDReferencePicker

#pragma mark - The candidates

/// The files under the folders things are kept in, of @a extensions:
/// the file system's one pass, not ListFilesTree's folder by folder.
+ (void)_files:(NSArray<NSString *> *)folders extensions:(NSString *)extensions stripped:(BOOL)stripped
          what:(NSString *)what into:(NSMutableArray<NSString *> *)names details:(NSMutableArray<NSString *> *)details
          seen:(NSMutableSet<NSString *> *)seen fileSystem:(idFileSystem *)fileSystem {
    for (NSString *path in [fileSystem filesUnder:folders extensions:[extensions componentsSeparatedByString:@"|"]]) {
        NSString *name = stripped ? path.stringByDeletingPathExtension : path;
        if ([seen containsObject:name.lowercaseString]) continue;
        [seen addObject:name.lowercaseString];
        [names addObject:name];
        [details addObject:what];
    }
}

+ (NSArray<NSString *> *)namesFor:(UDReferenceField *)field workspace:(UDWorkspace *)workspace
                          details:(NSMutableArray<NSString *> *)details {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    idDeclManager *declManager = workspace.declManager;
    idFileSystem *fileSystem = workspace.fileSystem;
    NSArray<NSString *> *imageFolders = @[@"textures", @"models", @"gfx", @"guis", @"lights", @"particles", @"env", @"fonts"];
    NSString *images = @".tga|.dds|.jpg|.png";
    switch (field.kind) {
        case UDReferenceNames:
            [names addObjectsFromArray:field.names ?: @[]];
            for (NSUInteger i = 0; i < names.count; i++) [details addObject:i < field.details.count ? field.details[i] : @""];
            return names;
        case UDReferenceMaterials:
        case UDReferenceDecls: {
            declType_t type = field.kind == UDReferenceMaterials ? DECL_MATERIAL : (declType_t)field.declType;
            for (idDeclBase *decl in [declManager declsOfType:type forceParse:NO]) {
                NSString *name = decl.name;
                if (name.length == 0 || [seen containsObject:name.lowercaseString]) continue;
                [seen addObject:name.lowercaseString];
                [names addObject:name];
                [details addObject:decl.fileName.lastPathComponent ?: @""];
            }
            if (field.kind == UDReferenceMaterials) {
                // an image is made a material of (idMaterial's default)
                [self _files:imageFolders extensions:images stripped:YES what:@"image" into:names details:details seen:seen fileSystem:fileSystem];
            }
            break;
        }
        case UDReferenceImages:
            [self _files:imageFolders extensions:images stripped:NO what:@"image" into:names details:details seen:seen fileSystem:fileSystem];
            break;
        case UDReferenceEntityModels:
            for (idDeclBase *decl in [declManager declsOfType:DECL_MODELDEF forceParse:NO]) {
                NSString *name = decl.name;
                if (name.length == 0 || [seen containsObject:name.lowercaseString]) continue;
                [seen addObject:name.lowercaseString];
                [names addObject:name];
                [details addObject:decl.fileName.lastPathComponent ?: @""];
            }
            // fall through: the model files
        case UDReferenceModels:
            [self _files:@[@"models"] extensions:@".lwo|.ase|.ma|.flt|.md5mesh|.md3" stripped:NO what:@"model"
                    into:names details:details seen:seen fileSystem:fileSystem];
            break;
        case UDReferenceVideos:
            [self _files:@[@"video"] extensions:@".roq" stripped:NO what:@"video" into:names details:details seen:seen fileSystem:fileSystem];
            break;
        case UDReferenceSounds:
            [self _files:@[@"sound"] extensions:@".wav|.ogg" stripped:NO what:@"sound" into:names details:details seen:seen fileSystem:fileSystem];
            break;
        case UDReferenceCubeMaps:
            // R_LoadCubeImages' first side: _px for a cube map, _forward for a camera's
            for (NSString *path in [fileSystem filesUnder:imageFolders extensions:[images componentsSeparatedByString:@"|"]]) {
                NSString *stem = path.stringByDeletingPathExtension;
                for (NSArray<NSString *> *side in @[@[@"_px", @"cube map"], @[@"_forward", @"camera cube map"]]) {
                    if (![stem.lowercaseString hasSuffix:side[0]]) continue;
                    NSString *name = [stem substringToIndex:stem.length - side[0].length];
                    if ([seen containsObject:name.lowercaseString]) continue;
                    [seen addObject:name.lowercaseString];
                    [names addObject:name];
                    [details addObject:side[1]];
                }
            }
            break;
        case UDReferencePrograms:
            // R_FindARBProgram's names: under glprogs/
            for (NSString *path in [fileSystem filesUnder:@[@"glprogs"] extensions:@[@".vfp", @".vp", @".fp"]]) {
                NSString *name = [path substringFromIndex:@"glprogs/".length];
                if ([seen containsObject:name.lowercaseString]) continue;
                [seen addObject:name.lowercaseString];
                [names addObject:name];
                [details addObject:@"program"];
            }
            break;
        case UDReferenceGuis:
            [self _files:@[@"guis"] extensions:@".gui" stripped:NO what:@"GUI" into:names details:details seen:seen fileSystem:fileSystem];
            break;
    }
    // sorted by name, their details with them
    NSArray<NSNumber *> *order = [[self _indexesOf:names] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [names[a.unsignedIntegerValue] caseInsensitiveCompare:names[b.unsignedIntegerValue]];
    }];
    NSMutableArray<NSString *> *sortedNames = [NSMutableArray array];
    NSMutableArray<NSString *> *sortedDetails = [NSMutableArray array];
    for (NSNumber *i in order) {
        [sortedNames addObject:names[i.unsignedIntegerValue]];
        [sortedDetails addObject:details[i.unsignedIntegerValue]];
    }
    [details setArray:sortedDetails];
    return sortedNames;
}

+ (NSArray<NSNumber *> *)_indexesOf:(NSArray *)array {
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray arrayWithCapacity:array.count];
    for (NSUInteger i = 0; i < array.count; i++) [indexes addObject:@(i)];
    return indexes;
}


- (instancetype)initWithTitle:(NSString *)title names:(NSArray<NSString *> *)names
                      details:(NSArray<NSString *> *)details current:(NSString *)current {
    self = [super initWithWindowNibName:@"UDReferencePicker" owner:self];
    if (self) {
        _pickerTitle = [title copy];
        _names = [names copy];
        NSMutableDictionary<NSString *, NSString *> *byName = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < details.count && i < names.count; i++) byName[names[i]] = details[i];
        _details = byName;
        _current = [current copy];
        _shownNames = _names;
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.titleLabel.stringValue = self.pickerTitle;
    self.filterField.delegate = self;
    self.table.target = self;
    self.table.doubleAction = @selector(ok:);
    [self filterChanged:nil];
}

- (void)beginSheetForWindow:(NSWindow *)window target:(id)target action:(SEL)action {
    self.target = target;
    self.action = action;
    NSWindow *sheet = self.window;
    [sheet makeFirstResponder:self.filterField];
    [NSApp beginSheet:sheet modalForWindow:window modalDelegate:self
       didEndSelector:@selector(_sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

/// The sheet down; on OK the target told. (On GNUstep -beginSheet:… runs
/// the sheet modally, and calls this as it returns.)
- (void)_sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [sheet orderOut:self];
    id target = self.target;
    // called, not sent: in an app-modal session (a PDA child's sheet's)
    // NSApp's sendAction:to:from: does not reach a target outside it
    if (returnCode == NSModalResponseOK && target != nil && self.action != NULL && [target respondsToSelector:self.action]) {
        void (*send)(id, SEL, id) = (void (*)(id, SEL, id))[target methodForSelector:self.action];
        send(target, self.action, self);
    }
}

#pragma mark - The filter (XFDPalettePanel's rebuildRowsWithFilter:)

- (void)controlTextDidChange:(NSNotification *)notification {
    [self filterChanged:notification.object];
}

/// The names containing the filter, in any case; the current one (or the
/// first) chosen.
- (IBAction)filterChanged:(id)sender {
    NSString *filter = [self.filterField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (filter.length == 0) {
        self.shownNames = self.names;
    } else {
        NSMutableArray<NSString *> *shown = [NSMutableArray array];
        for (NSString *name in self.names) {
            if ([name rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) [shown addObject:name];
        }
        self.shownNames = shown;
    }
    [self.table reloadData];
    NSUInteger row = self.current != nil ? [self.shownNames indexOfObject:self.current] : NSNotFound;
    if (row == NSNotFound && self.shownNames.count > 0) row = 0;
    if (row != NSNotFound) {
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [self.table scrollRowToVisible:(NSInteger)row];
    } else {
        [self.table deselectAll:nil];
    }
    self.countLabel.stringValue = [NSString stringWithFormat:@"%lu of %lu", (unsigned long)self.shownNames.count,
                                   (unsigned long)self.names.count];
    self.okButton.enabled = self.shownNames.count > 0;
}

/// Up and down in the filter move the table's choice; Return chooses.
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    NSInteger row = self.table.selectedRow;
    if (command == @selector(moveDown:) || command == @selector(moveUp:)) {
        NSInteger next = row + (command == @selector(moveDown:) ? 1 : -1);
        if (next >= 0 && next < (NSInteger)self.shownNames.count) {
            [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)next] byExtendingSelection:NO];
            [self.table scrollRowToVisible:next];
        }
        return YES;
    }
    if (command == @selector(insertNewline:)) {
        [self ok:nil];
        return YES;
    }
    if (command == @selector(cancelOperation:)) {
        [self cancel:nil];
        return YES;
    }
    return NO;
}

- (IBAction)ok:(id)sender {
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.shownNames.count) {
        NSBeep();
        return;
    }
    self.chosenName = self.shownNames[(NSUInteger)row];
    [NSApp endSheet:self.window returnCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [NSApp endSheet:self.window returnCode:NSModalResponseCancel];
}

/// Escape, through the panel's responders.
- (void)cancelOperation:(id)sender {
    [self cancel:sender];
}

#pragma mark - The table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.shownNames.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.shownNames.count) return nil;
    NSString *name = self.shownNames[(NSUInteger)row];
    return [column.identifier isEqualToString:@"detail"] ? self.details[name] : name;
}

@end
