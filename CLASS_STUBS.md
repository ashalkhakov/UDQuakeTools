
```objc name=UD_CLASS_STUBS.md
/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDQuakeTools - Initial class/interface stubs
 */

#pragma mark - UDCore (Foundation)

/* UDContentSource.h */
@protocol UDContentSource <NSObject>
- (uint64_t)length;
- (NSData *)readRange:(NSRange)range error:(NSError **)error;
@optional
- (NSData *)readAll:(NSError **)error;
@end

/* UDArchiveEntry.h */
@interface UDArchiveEntry : NSObject
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) uint64_t size;
@property (nonatomic, readonly, copy) NSString *contentType;
@property (nonatomic, readonly, copy) NSDate *modifiedAt;

/* lazy payload source from original archive */
@property (nonatomic, strong) id<UDContentSource> source;
/* replacement payload source used by editor before save */
@property (nonatomic, strong) id<UDContentSource> stagedSource;
@end

/* UDDirectoryNode.h */
@interface UDDirectoryNode : NSObject
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSArray *children; // UDDirectoryNode|UDArchiveEntry
@end

/* UDArchive.h */
@interface UDArchive : NSObject
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, copy) NSArray<UDArchiveEntry *> *entries;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *metadata;
@end

/* UDArchiveMutation.h */
@interface UDArchiveMutation : NSObject
@property (nonatomic, readonly, copy) NSString *kind; // add/remove/move/replace/mkdir
@property (nonatomic, readonly, copy) NSDictionary *payload;
@property (nonatomic, readonly, copy) NSDate *createdAt;
@end

/* UDArchiveEditor.h */
@interface UDArchiveEditor : NSObject
@property (nonatomic, readonly, strong) UDArchive *archive;
@property (nonatomic, readonly, copy) NSArray<UDArchiveMutation *> *pendingMutations;
@property (nonatomic, readonly, getter=isDirty) BOOL dirty;

- (instancetype)initWithArchive:(UDArchive *)archive;

- (BOOL)addSource:(id<UDContentSource>)source atPath:(NSString *)path error:(NSError **)error;
- (BOOL)removeNodeAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)moveNodeFromPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error;
- (BOOL)replaceEntryAtPath:(NSString *)path withSource:(id<UDContentSource>)source error:(NSError **)error;

- (NSData *)contentForEntryAtPath:(NSString *)path range:(NSRange)range error:(NSError **)error;

- (void)applyMutation:(UDArchiveMutation *)mutation;
- (void)revertAll;
@end

#pragma mark - UDFormats (Foundation)

/* UDArchiveCodec.h */
@protocol UDArchiveCodec <NSObject>
@property (nonatomic, readonly, copy) NSString *formatIdentifier; // e.g. com.udquake.pak

- (BOOL)canReadURL:(NSURL *)url;
- (UDArchive *)readArchiveFromURL:(NSURL *)url error:(NSError **)error;

- (BOOL)writeArchive:(UDArchive *)archive toURL:(NSURL *)url error:(NSError **)error;
- (BOOL)writeEditedArchive:(UDArchiveEditor *)editor toURL:(NSURL *)url error:(NSError **)error;
@end

/* UDCodecRegistry.h */
@interface UDCodecRegistry : NSObject
+ (instancetype)sharedRegistry;
- (void)registerCodec:(id<UDArchiveCodec>)codec;
- (id<UDArchiveCodec>)codecForURL:(NSURL *)url typeName:(NSString *)typeName;
- (id<UDArchiveCodec>)codecForFormatIdentifier:(NSString *)formatIdentifier;
@end

/* UDPAKCodec.h */
@interface UDPAKCodec : NSObject <UDArchiveCodec>
@end

/* UDPAKEntrySource.h */
@interface UDPAKEntrySource : NSObject <UDContentSource>
- (instancetype)initWithFileURL:(NSURL *)fileURL
                         offset:(uint64_t)offset
                         length:(uint64_t)length;
@end

/* UDStagedFileSource.h */
@interface UDStagedFileSource : NSObject <UDContentSource>
- (instancetype)initWithFileURL:(NSURL *)fileURL;
@end

/* UDFileRangeReader.h */
@interface UDFileRangeReader : NSObject
- (instancetype)initWithURL:(NSURL *)url;
- (NSData *)readRange:(NSRange)range error:(NSError **)error;
- (uint64_t)length;
@end

/* UDAtomicFileWriter.h */
@interface UDAtomicFileWriter : NSObject
+ (BOOL)replaceItemAtURL:(NSURL *)dstURL
             withItemAtURL:(NSURL *)tmpURL
               backupSuffix:(NSString *)backupSuffix
                     error:(NSError **)error;
@end

#pragma mark - UDApp (AppKit)

/* UDArchiveDocument.h */
@interface UDArchiveDocument : NSDocument
@property (nonatomic, strong) UDArchive *archive;
@property (nonatomic, strong) UDArchiveEditor *editor;
@property (nonatomic, strong) id<UDArchiveCodec> codec;
@end

/* UDArchiveBrowserViewController.h */
@interface UDArchiveBrowserViewController : NSViewController
- (void)bindToDocument:(UDArchiveDocument *)document;
@end

/* UDPreviewPaneController.h */
@interface UDPreviewPaneController : NSViewController
- (void)previewEntryAtPath:(NSString *)path fromDocument:(UDArchiveDocument *)document;
@end
```

