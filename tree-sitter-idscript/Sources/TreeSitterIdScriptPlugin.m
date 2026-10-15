/*---------------------------------------------------------------------------------------------
 *  TreeSitterIdScriptPlugin.m
 *--------------------------------------------------------------------------------------------*/

#import "TreeSitterIdScriptPlugin.h"

// Forward-declare the tree-sitter language factory.
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_idscript(void);

@implementation TreeSitterIdScriptPlugin {
    NSBundle *_bundle;
}


- (void)extensionDidLoad:(NSBundle *)bundle {
    _bundle = bundle;
    NSLog(@"TreeSitterIdScriptPlugin: loaded from %@", bundle.bundlePath);
}

- (void)extensionWillUnload:(NSBundle *)bundle {
    NSLog(@"TreeSitterIdScriptPlugin: will unload %@", bundle.bundlePath);
    _bundle = nil;
}

- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"idscript"]) return tree_sitter_idscript;
    return NULL;
}

@end
