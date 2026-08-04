//
//  UDDeclBrowser.h
//  PakManager
//
//  Created by artyom on 8/2/26.
//

#import "UDPathTree.h"

@class UDWorkspace, UDDeclBrowser;
@class idDecl;

@interface UDDeclSearchMatch : NSObject
@property (strong) UDDeclTreeNode *node;       // or store type+index / the idDecl*
@property (assign) NSRange matchRange;         // optional, for later highlighting
@end

@interface UDDeclSearchFileGroup : NSObject
@property (copy)   NSString *filename;         // "materials/berserkhelmet.mtr" or just the base name
@property (strong) NSMutableArray<UDDeclSearchMatch *> *matches;
@end

@protocol UDDeclBrowserDelegate <NSObject>
@optional
- (void)declBrowser:(UDDeclBrowser *)browser didSelectDecl:(const idDecl *)decl;
- (void)declBrowser:(UDDeclBrowser *)browser didSelectGuiOrScript:(NSString *)fileName;
- (void)declBrowserDidClearSelection:(UDDeclBrowser *)browser;
@end

@interface UDDeclBrowser : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (strong, nonatomic, readonly) UDWorkspace *workspace;
@property (weak) id<UDDeclBrowserDelegate> delegate;

- (instancetype)initWithWorkspace:(UDWorkspace *)workspace;

- (void)reset;
- (void)findByName:(NSString *)name;
- (void)findContaining:(NSString *)text;

- (void)attachToOutlineViews:(NSOutlineView *)outlineView searchOutline:(NSOutlineView *)searchOutlineView;

@end
