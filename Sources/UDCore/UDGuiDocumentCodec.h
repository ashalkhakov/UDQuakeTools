/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiDocumentCodec.h — parse/serialize GUI documents.
 */

#import <Foundation/Foundation.h>

#import "UDGuiModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiDocumentCodec : NSObject

- (nullable UDGuiDocument *)parseDocumentFromText:(NSString *)text
                                sourceVirtualPath:(NSString *)sourceVirtualPath
                                            error:(NSError **)error;

- (nullable NSString *)serializeDocument:(UDGuiDocument *)document error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
