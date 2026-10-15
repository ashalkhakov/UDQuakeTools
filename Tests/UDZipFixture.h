#import <Foundation/Foundation.h>
#import "UDZipWriter.h"

NS_ASSUME_NONNULL_BEGIN

/// Builds an in-memory ZIP fixture. Each entry is @[path, UTF-8 payload,
/// @(UDZipCompressionMethod)]; the method is honoured exactly, so a fixture
/// can mix deflated and stored entries. Returns nil if the writer fails.
NSData * _Nullable UDZipFixtureData(NSArray<NSArray *> *entries);

NS_ASSUME_NONNULL_END
