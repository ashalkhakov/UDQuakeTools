#import <AppKit/NSDocument.h>

#import "UDWorkspace.h"

@interface UDWorkspaceDocument : NSDocument
@property (nonatomic, strong) UDWorkspace *workspace;
@property (nonatomic, strong) NSMutableDictionary *workspaceConfig;

- (BOOL)showSettingsForced;
- (BOOL)isConfigured;
- (void)applySettingsAndCreateWorkspace;

-(void)refreshUI;
@end
