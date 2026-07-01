/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl persistence adapter implementations.
 */

#import "UDDeclPersistence.h"

static NSString *const UDDeclParserErrorDomain = @"com.udquake.error.declparser";

@implementation UDVFSDeclPersistenceAdapter

@synthesize virtualFileSystem = _virtualFileSystem;

- (instancetype)initWithVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem {
    NSParameterAssert(virtualFileSystem != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _virtualFileSystem = virtualFileSystem;
    return self;
}

- (nullable NSString *)readDeclTextAtVirtualPath:(NSString *)virtualPath
                                           error:(NSError **)error {
    NSData *data = [self.virtualFileSystem readFileAtPath:virtualPath error:error];
    if (!data) {
        return nil;
    }

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }

    if (!text && error) {
        *error = [NSError errorWithDomain:UDDeclParserErrorDomain
                                     code:4
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unable to decode decl file."}];
    }
    return text;
}

- (BOOL)writeDeclText:(NSString *)text
         toVirtualPath:(NSString *)virtualPath
                 error:(NSError **)error {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    return [self.virtualFileSystem writeFileAtPath:virtualPath data:data error:error];
}

@end
