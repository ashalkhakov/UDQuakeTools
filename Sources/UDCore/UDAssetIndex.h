#import <Foundation/Foundation.h>

#import "UDVirtualFileSystem.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDAssetKind) {
    UDAssetKindUnknown = 0,
    UDAssetKindDecl,
    UDAssetKindMaterial,
    UDAssetKindGUI,
    UDAssetKindScript,
};

@interface UDAssetIndexEntry : NSObject {
    NSString *_virtualPath;
    NSString *_name;
    NSString *_fileExtension;
    UDAssetKind _kind;
    NSString *_mountIdentifier;
    NSURL *_sourceURL;
    NSString *_sourcePath;
    BOOL _archiveBacked;
}

@property (nonatomic, readonly, copy) NSString *virtualPath;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *fileExtension;
@property (nonatomic, readonly) UDAssetKind kind;
@property (nonatomic, readonly, copy) NSString *mountIdentifier;
@property (nonatomic, readonly, strong) NSURL *sourceURL;
@property (nonatomic, readonly, copy) NSString *sourcePath;
@property (nonatomic, readonly, getter=isArchiveBacked) BOOL archiveBacked;

- (instancetype)initWithVirtualPath:(NSString *)virtualPath
                               name:(NSString *)name
                      fileExtension:(NSString *)fileExtension
                               kind:(UDAssetKind)kind
                    mountIdentifier:(NSString *)mountIdentifier
                          sourceURL:(NSURL *)sourceURL
                         sourcePath:(NSString *)sourcePath
                      archiveBacked:(BOOL)archiveBacked NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface UDAssetIndex : NSObject {
    NSArray<UDAssetIndexEntry *> *_entries;
}

@property (nonatomic, readonly, copy) NSArray<UDAssetIndexEntry *> *entries;

- (instancetype)initWithEntries:(NSArray<UDAssetIndexEntry *> *)entries NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<UDAssetIndexEntry *> *)entriesOfKind:(UDAssetKind)kind;
- (nullable UDAssetIndexEntry *)entryForVirtualPath:(NSString *)virtualPath;

@end

@interface UDAssetIndexer : NSObject

- (UDAssetIndex *)buildIndexFromVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END