/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEventsProcessingService.m — Service for processing GUI script events.
 */

#import "UDGuiEventsProcessingService.h"

@interface UDGuiEventsProcessingService () {
    UDGuiDocumentCodec *_codec;
}
@end

@implementation UDGuiEventsProcessingService

- (instancetype)init {
    self = [self initWithCodec:[[UDGuiDocumentCodec alloc] init]];
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithCodec:(UDGuiDocumentCodec *)codec {
    self = [super init];
    if (self) {
        _codec = codec;
    }
    return self;
}

- (NSString *)serializeCommands:(NSArray<UDGuiScriptCommand *> *)commands {
    NSMutableString *text = [NSMutableString string];
    for (UDGuiScriptCommand *command in commands) {
        if ([command.keyword isEqualToString:@"__ud_raw_script_body__"]) {
            NSString *rawBody = command.arguments ?: @"";
            [text appendString:rawBody];
        } else {
            if ([command isKindOfClass:[UDGuiIfCommand class]]) {
                [text appendFormat:@"%@\n", [_codec serializeScriptCommand:command]];
            } else {
                [text appendFormat:@"%@ ;\n", [_codec serializeScriptCommand:command]];
            }
        }
    }
    return [text copy];
}

- (nullable NSArray<UDGuiScriptCommand *> *)parseCommandsFromText:(NSString *)text error:(NSError **)error {
    return [_codec scriptCommandsFromBlockValue:text error:error];
}

- (BOOL)areCommands:(NSArray<UDGuiScriptCommand *> *)commandsA equalToCommands:(NSArray<UDGuiScriptCommand *> *)commandsB {
    if (commandsA.count != commandsB.count) {
        return NO;
    }
    for (NSUInteger idx = 0; idx < commandsA.count; idx++) {
        NSString *aStr = [_codec serializeScriptCommand:[commandsA objectAtIndex:idx]];
        NSString *bStr = [_codec serializeScriptCommand:[commandsB objectAtIndex:idx]];
        if (![aStr isEqualToString:bStr]) {
            return NO;
        }
    }
    return YES;
}

@end
