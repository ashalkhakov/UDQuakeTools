#import "idDeclManager.h"
#import "UDWorkspace.h"
#import "UDDeclItem.h"

@implementation UDDeclItem

- (instancetype)initWithType:(declType_t)type declName:(NSString *)declName path:(NSString *)path {
    NSString *name = path.lastPathComponent;
    self = [super initWithName:name path:path];
    if (self) {
        _type = type;
        _declName = declName;
    }
    return self;
}

- (UDWorkspaceItemKind)kind {
    return UDWorkspaceItemKindDecl;
}

- (NSString *)text:(UDWorkspace *)workspace {
    NSMutableData *declText = [[NSMutableData alloc] init];
    idDeclBase *decl = [workspace.declManager declByName:self.declName type:_type forceParse:NO error:nil];
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
