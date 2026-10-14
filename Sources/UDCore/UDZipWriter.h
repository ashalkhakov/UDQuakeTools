/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDZipWriter — builds a ZIP archive (PK3/PK4) in memory on top of zlib.
 *
 * Reading ZIPs goes through the minizip unzip.c ported with the Doom 3 file
 * system; this is the writing half, so the toolkit needs nothing beyond
 * zlib. Archives are plain PKWARE ZIP 2.0: no ZIP64, no encryption, no data
 * descriptors — exactly what idTech engines read. Entry names are stored as
 * UTF-8 (general purpose flag bit 11).
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDZipCompressionMethod) {
    /** Store the bytes as-is (ZIP method 0). */
    UDZipCompressionMethodStored = 0,
    /** Always deflate (ZIP method 8), even when that does not shrink the entry. */
    UDZipCompressionMethodDeflated = 8,
    /** Deflate, falling back to stored when deflating does not shrink the entry. */
    UDZipCompressionMethodAutomatic = -1,
};

extern NSString *const UDZipWriterErrorDomain;

@interface UDZipWriter : NSObject

/** Number of entries added so far. */
@property (nonatomic, readonly) NSUInteger entryCount;

/**
 * Appends one entry. modificationDate may be nil (the current time is used);
 * dates before 1980 are clamped, as ZIP cannot represent them. Fails when
 * the archive would need ZIP64 (an entry or the archive over 4 GiB, or more
 * than 65535 entries) or when deflating fails.
 */
- (BOOL)addEntryWithPath:(NSString *)path
                    data:(NSData *)data
                  method:(UDZipCompressionMethod)method
        modificationDate:(nullable NSDate *)modificationDate
                   error:(NSError **)error;

/** The complete archive: every entry added so far plus the central directory. */
- (NSData *)archiveData;

/** Writes -archiveData to url atomically. */
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
