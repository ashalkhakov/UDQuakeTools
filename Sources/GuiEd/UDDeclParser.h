/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclParser.h — Decl parsing interfaces and id-style token helpers.
 */

#import <Foundation/Foundation.h>

#import "UDDeclModel.h"
#import "UDToken.h"
#import "UDIdLexer.h"
#import "UDIdParser.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDeclParser : NSObject

- (NSArray<UDDeclDefinition *> *)parseDefinitionsFromText:(NSString *)text
                                         sourceVirtualPath:(NSString *)sourceVirtualPath
                                                     error:(NSError **)error;

- (NSString *)serializeDefinitions:(NSArray<UDDeclDefinition *> *)definitions;

@end

NS_ASSUME_NONNULL_END
