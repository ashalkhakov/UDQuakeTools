/*---------------------------------------------------------------------------------------------
 *  TreeSitterIdDeclPlugin.h  —  Principal class for the TreeSitterIdDecl bundle.
 *
 *  Conforms to UDExtension: the tree-sitter language factory is provided via
 *  -languageFuncForIdentifier: (no dlsym required).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDCodeKit/UDExtension.h>

NS_ASSUME_NONNULL_BEGIN

@interface TreeSitterIdDeclPlugin : NSObject <UDExtension>


@end

NS_ASSUME_NONNULL_END
