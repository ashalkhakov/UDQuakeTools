/*---------------------------------------------------------------------------------------------
 *  UQPakDocument.h
 *
 *  A pak (.pak, .pk3, .pk4), in UDCode as a custom document (UDCodeKit's
 *  UDCustomDocument): its model Pak Manager's, a UDArchiveDocument whose
 *  archive editor adds, renames and deletes entries, saved over the file;
 *  edited in Pak Manager's browser (UDArchiveBrowserController). It has no
 *  text: it isn't shown as text.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDCodeKit/UDCodeKit.h>

@class UDArchiveDocument;

NS_ASSUME_NONNULL_BEGIN

@interface UQPakDocument : NSObject <UDCustomDocument>

/// Whether the file at @a url is one of the paks Pak Manager reads (by its extension).
+ (BOOL)isPakURL:(NSURL *)url;

/// The pak at @a url, read; nil and why.
- (nullable instancetype)initWithURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;

@property (nonatomic, readonly, copy) NSURL *URL;
@property (nonatomic, readonly) UDArchiveDocument *archiveDocument;

@end

NS_ASSUME_NONNULL_END
