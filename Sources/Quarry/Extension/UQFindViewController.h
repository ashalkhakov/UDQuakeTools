/*---------------------------------------------------------------------------------------------
 *  UQFindViewController.h
 *
 *  Quarry's Find (text contains), in UDCode's bottom area: the decls,
 *  scripts and GUIs whose text has what is typed, grouped by what they are
 *  (their type, their folder), each opened in its tab when chosen. Laid out
 *  in UQFind.xib.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

@class UQProject;

NS_ASSUME_NONNULL_BEGIN

@interface UQFindViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

- (instancetype)initWithProject:(UQProject *)project;

@property (nonatomic, weak, readonly, nullable) IBOutlet NSSearchField *searchField;
@property (nonatomic, weak, readonly, nullable) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak, readonly, nullable) IBOutlet NSTextField *statusField;

/// What was found: groups (their names), then their items' URLs.
@property (nonatomic, readonly, copy) NSArray<NSString *> *groupNames;
- (NSArray<NSURL *> *)URLsInGroup:(NSString *)group;

/// The search field's text looked for.
- (IBAction)search:(nullable id)sender;
/// The chosen match opened in its tab.
- (IBAction)openMatch:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
