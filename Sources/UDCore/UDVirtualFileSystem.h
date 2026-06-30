#import <Foundation/Foundation.h>
#import "UDContentSource.h"
#import "UDVFSMount.h"
#import "UDGame.h"

@class UDCodecRegistry;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const UDVFSDidWriteFileNotification;
extern NSString *const UDVFSNotificationVirtualPathKey;
extern NSString *const UDVFSNotificationFileURLKey;
extern NSString *const UDVFSNotificationMountIdentifierKey;

@interface UDVFSResolvedFile : NSObject {
    NSString *_virtualPath;
    UDVFSMount *_mount;
    id<UDContentSource> _contentSource;
    uint64_t _length;
    NSString *_sourcePath;
    NSURL *_fileURL;
}

@property (nonatomic, readonly, copy) NSString *virtualPath;
@property (nonatomic, readonly, strong) UDVFSMount *mount;
@property (nonatomic, readonly, strong) id<UDContentSource> contentSource;
@property (nonatomic, readonly) uint64_t length;
@property (nonatomic, readonly, copy) NSString *sourcePath;
@property (nonatomic, readonly, nullable, strong) NSURL *fileURL;

- (instancetype)initWithVirtualPath:(NSString *)virtualPath
                              mount:(UDVFSMount *)mount
                        contentSource:(id<UDContentSource>)contentSource
                             length:(uint64_t)length
                         sourcePath:(NSString *)sourcePath
                            fileURL:(nullable NSURL *)fileURL NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface UDVirtualFileSystem : NSObject {
    UDCodecRegistry *_codecRegistry;
    NSMutableArray<UDVFSMount *> *_mounts;
    NSMutableDictionary<NSString *, id> *_mountAdapters;
    NSUInteger _nextMountOrder;
    UDGameType _gameType;
    NSURL *_gameDirectoryURL;
}

@property (nonatomic, readonly, copy) NSArray<UDVFSMount *> *mounts;
@property (nonatomic, readonly) UDGameType gameType;
@property (nonatomic, readonly, nullable, strong) NSURL *gameDirectoryURL;

- (instancetype)init;
- (instancetype)initWithCodecRegistry:(UDCodecRegistry *)codecRegistry NS_DESIGNATED_INITIALIZER;

- (void)configureWithGameType:(UDGameType)gameType
             gameDirectoryURL:(nullable NSURL *)gameDirectoryURL;

- (nullable UDVFSMount *)mountDirectoryURL:(NSURL *)directoryURL
                                identifier:(NSString *)identifier
                               virtualRoot:(nullable NSString *)virtualRoot
                                  priority:(NSInteger)priority
                                     error:(NSError **)error;

- (nullable UDVFSMount *)mountArchiveURL:(NSURL *)archiveURL
                              identifier:(NSString *)identifier
                             virtualRoot:(nullable NSString *)virtualRoot
                                priority:(NSInteger)priority
                                typeName:(nullable NSString *)typeName
                                   error:(NSError **)error;

- (NSArray<UDVFSMount *> *)mountDiscoveredArchivesInGameDirectory:(NSError **)error;

- (BOOL)unmountIdentifier:(NSString *)identifier;

- (BOOL)fileExistsAtPath:(NSString *)virtualPath;
- (nullable UDVFSResolvedFile *)resolvedFileAtPath:(NSString *)virtualPath error:(NSError **)error;
- (NSArray<UDVFSResolvedFile *> *)visibleFilesWithExtensions:(nullable NSSet<NSString *> *)extensions error:(NSError **)error;
- (nullable NSData *)readFileAtPath:(NSString *)virtualPath error:(NSError **)error;
- (BOOL)writeFileAtPath:(NSString *)virtualPath data:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
