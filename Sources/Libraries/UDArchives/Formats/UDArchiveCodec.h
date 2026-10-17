#import <Foundation/Foundation.h>

@class UDArchive;
@class UDArchiveEditor;

NS_ASSUME_NONNULL_BEGIN

@protocol UDArchiveCodec <NSObject>
@property (nonatomic, readonly, copy) NSString *formatIdentifier;

- (BOOL)canReadURL:(NSURL *)url;
- (nullable UDArchive *)readArchiveFromURL:(NSURL *)url error:(NSError **)error;
- (BOOL)writeArchive:(UDArchive *)archive toURL:(NSURL *)url error:(NSError **)error;
- (BOOL)writeEditedArchive:(UDArchiveEditor *)editor toURL:(NSURL *)url error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
