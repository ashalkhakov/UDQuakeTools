/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclElement.m — the elements of a decl's transient lists.
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclElement.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

NSNotificationName const UDDeclElementWillBeReplacedNotification = @"UDDeclElementWillBeReplacedNotification";
NSNotificationName const UDDeclElementWasReplacedNotification = @"UDDeclElementWasReplacedNotification";

@implementation UDDeclElement

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] init];
}

/// Its decl puts @a edited in this element's place, in a new array; NO when
/// it is in none.
- (BOOL)ud_replaceInOwnerWith:(UDDeclElement *)edited {
    UDDeclBase *owner = self.ud_owner;
    NSString *key = self.ud_ownerKey;
    if (owner == nil || key == nil) {
        return NO;
    }
    NSMutableArray *elements = [[owner valueForKey:key] mutableCopy];
    NSUInteger index = [elements indexOfObjectIdenticalTo:self];
    if (index == NSNotFound) {
        return NO;
    }
    elements[index] = edited;
    [[NSNotificationCenter defaultCenter] postNotificationName:UDDeclElementWillBeReplacedNotification object:owner];
    [owner setValue:elements forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDDeclElementWasReplacedNotification object:owner];
    return YES;
}

@end

@implementation UDDeclPropertyElement

/// Its values: its class's declared properties.
+ (NSArray<NSString *> *)ud_valueKeys {
    static NSMutableDictionary<NSString *, NSArray<NSString *> *> *keysByClass;
    @synchronized ([UDDeclPropertyElement class]) {
        if (keysByClass == nil) keysByClass = [NSMutableDictionary dictionary];
        NSString *className = NSStringFromClass(self);
        NSArray<NSString *> *keys = keysByClass[className];
        if (keys == nil) {
            NSMutableArray<NSString *> *names = [NSMutableArray array];
            unsigned int count = 0;
            objc_property_t *properties = class_copyPropertyList(self, &count);
            for (unsigned int i = 0; i < count; i++) {
                [names addObject:[NSString stringWithUTF8String:property_getName(properties[i])]];
            }
            free(properties);
            keys = keysByClass[className] = [names copy];
        }
        return keys;
    }
}

+ (NSSet<NSString *> *)ud_numberKeys {
    return [NSSet set];
}

- (id)copyWithZone:(NSZone *)zone {
    UDParticleStage *copy = [[[self class] alloc] init];
    for (NSString *key in [[self class] ud_valueKeys]) {
        [copy ud_setValue:[self valueForKey:key] forKey:key];
    }
    return copy;
}

- (void)ud_setValue:(id)value forKey:(NSString *)key {
    [super setValue:value forKey:key];
}

// A binding's edit: an edited copy in its place, so that it is its decl's
// (undoable, the decl updated).
- (void)setValue:(id)value forKey:(NSString *)key {
    if (self.ud_owner == nil || ![[[self class] ud_valueKeys] containsObject:key]) {
        [super setValue:value forKey:key];
        return;
    }
    UDParticleStage *edited = [self copy];
    [edited ud_setValue:value forKey:key];
    if (![self ud_replaceInOwnerWith:edited]) {
        [super setValue:value forKey:key];
    }
}

// A number typed in: a number, not text that KVC would make 0.
- (BOOL)validateValue:(id *)ioValue forKey:(NSString *)key error:(NSError **)error {
    objc_property_t property = class_getProperty([self class], key.UTF8String);
    const char *type = property != NULL ? property_getAttributes(property) : NULL;
    BOOL scalar = type != NULL && (type[1] == 'f' || type[1] == 'i');
    if ([[[self class] ud_numberKeys] containsObject:key] && [*ioValue isKindOfClass:[NSString class]] &&
        [[*ioValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
        *ioValue = nil;                                             // none
        return YES;
    }
    BOOL number = scalar || [[[self class] ud_numberKeys] containsObject:key];
    if (!number || ![*ioValue isKindOfClass:[NSString class]]) {
        return [super validateValue:ioValue forKey:key error:error];
    }
    NSScanner *scanner = [NSScanner scannerWithString:[*ioValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    double d = 0;
    int i = 0;
    BOOL integer = scalar && type[1] == 'i';
    BOOL scanned = integer ? [scanner scanInt:&i] : [scanner scanDouble:&d];
    if (scanned && scanner.isAtEnd) {
        *ioValue = integer ? @(i) : @((float)d);
        return YES;
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"UDDeclElement" code:1 userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"%@ is a %@number.", key, integer ? @"whole " : @""]}];
    }
    return NO;
}

@end
