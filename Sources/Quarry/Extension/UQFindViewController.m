/*---------------------------------------------------------------------------------------------
 *  UQFindViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UQFindViewController.h"
#import "UQProject.h"
#import "UDWorkspaceItem.h"

/// A match: its label, and the URL it opens.
@interface UQFindMatch : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSURL *URL;
@end

@implementation UQFindMatch
@end

@interface UQFindViewController ()
@property (nonatomic, weak) IBOutlet NSSearchField *searchField;
@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak) IBOutlet NSTextField *statusField;
@end

@implementation UQFindViewController {
    __weak UQProject *_project;
    NSArray<NSString *> *_groups;
    NSDictionary<NSString *, NSArray<UQFindMatch *> *> *_matches;
}

- (instancetype)initWithProject:(UQProject *)project {
    if (!(self = [super initWithNibName:@"UQFind" bundle:[NSBundle bundleForClass:[UQFindViewController class]]])) return nil;
    _project = project;
    _groups = @[];
    _matches = @{};
    self.title = @"Find in Decls";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _outlineView.target = self;
    _outlineView.doubleAction = @selector(openMatch:);
}

- (NSArray<NSString *> *)groupNames {
    return _groups;
}

- (NSArray<NSURL *> *)URLsInGroup:(NSString *)group {
    return [_matches[group] valueForKey:@"URL"] ?: @[];
}

- (IBAction)search:(id)sender {
    NSString *query = _searchField.stringValue ?: @"";
    NSMutableDictionary<NSString *, NSMutableArray<UQFindMatch *> *> *groups = [NSMutableDictionary dictionary];
    NSUInteger count = 0;
    for (UDWorkspaceItem *item in [_project itemsContainingText:query]) {
        NSURL *url = [_project URLOfItem:item];
        if (!url) continue;
        // its group: its type's (a decl's), its folder's (a file's)
        NSString *group = item.path.pathComponents.firstObject ?: @"";
        UQFindMatch *match = [[UQFindMatch alloc] init];
        match.label = item.path.length > group.length + 1 ? [item.path substringFromIndex:group.length + 1] : item.name;
        match.URL = url;
        if (!groups[group]) groups[group] = [NSMutableArray array];
        [groups[group] addObject:match];
        count++;
    }
    _groups = [groups.allKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    for (NSMutableArray<UQFindMatch *> *matches in groups.allValues) {
        [matches sortUsingComparator:^NSComparisonResult(UQFindMatch *a, UQFindMatch *b) { return [a.label caseInsensitiveCompare:b.label]; }];
    }
    _matches = groups;
    [_outlineView reloadData];
    for (NSString *group in _groups) [_outlineView expandItem:group];
    _statusField.stringValue = query.length ? [NSString stringWithFormat:@"%lu found", (unsigned long)count] : @"";
}

- (IBAction)openMatch:(id)sender {
    id item = [_outlineView itemAtRow:_outlineView.clickedRow >= 0 ? _outlineView.clickedRow : _outlineView.selectedRow];
    if ([item isKindOfClass:[UQFindMatch class]]) [_project.workbench showURL:[(UQFindMatch *)item URL]];
}

// ---------------------------------------------------------------------------
// MARK: - The outline: groups, then their matches
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) return (NSInteger)_groups.count;
    return [item isKindOfClass:[NSString class]] ? (NSInteger)_matches[item].count : 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return item ? _matches[item][(NSUInteger)index] : _groups[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[NSString class]];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item {
    return [item isKindOfClass:[UQFindMatch class]] ? [(UQFindMatch *)item label] : item;
}

@end
