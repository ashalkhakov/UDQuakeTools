#import "idDeclManager.h"
#import "UDWorkspace.h"
#import "UDDeclItem.h"

@implementation UDDeclItem

- (instancetype)initWithType:(declType_t)type path:(NSString *)path {
    NSString *name = path.lastPathComponent;
    self = [super initWithName:name path:path];
    if (self) {
        _type = type;
    }
    return self;
}

- (UDWorkspaceItemKind)kind {
    return UDWorkspaceItemKindDecl;
}

- (NSString *)text:(UDWorkspace *)workspace {
    NSMutableData *declText = [[NSMutableData alloc] init];
    idDecl *decl = [workspace.declManager declByName:self.path type:_type forceParse:NO error:nil];
    if (!decl) {
        return @"";
    }
    [decl text:declText];

    NSString *text = [[NSString alloc] initWithData:declText encoding:NSUTF8StringEncoding];
    return text;
}

- (BOOL)matchesTextSearch:(NSString *)query inWorkspace:(UDWorkspace *)workspace {
    if (query.length == 0) return YES;
    NSString *t = [self text:workspace];
    if (!t) return NO;
    return [t rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
}

@end
