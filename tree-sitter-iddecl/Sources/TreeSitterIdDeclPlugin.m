/*---------------------------------------------------------------------------------------------
 *  TreeSitterIdDeclPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterIdDeclPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_iddecl(void);

@implementation TreeSitterIdDeclPlugin {
    NSBundle *_bundle;
}


- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterIdDeclPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterIdDeclPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"iddecl"]) return tree_sitter_iddecl;
    return NULL;
}

@end
