/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEventsProcessingService.h — Service for processing GUI script events (serialize, parse, compare).
 */

#import <Foundation/Foundation.h>
#import "UDGuiModel.h"
#import "UDGuiDocumentCodec.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiEventsProcessingService : NSObject

- (instancetype)initWithCodec:(UDGuiDocumentCodec *)codec NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSString *)serializeCommands:(NSArray<UDGuiScriptCommand *> *)commands;
- (nullable NSArray<UDGuiScriptCommand *> *)parseCommandsFromText:(NSString *)text error:(NSError **)error;
- (BOOL)areCommands:(NSArray<UDGuiScriptCommand *> *)commandsA equalToCommands:(NSArray<UDGuiScriptCommand *> *)commandsB;

@end

NS_ASSUME_NONNULL_END
