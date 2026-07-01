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

@interface UDDeclDefinition : NSObject {
    NSString *_declType;
    NSString *_declName;
    NSString *_body;
    NSString *_sourceVirtualPath;
}

@property (nonatomic, readonly, copy) NSString *declType;
@property (nonatomic, readonly, copy) NSString *declName;
@property (nonatomic, readonly, copy) NSString *body;
@property (nonatomic, readonly, copy) NSString *sourceVirtualPath;

- (instancetype)initWithDeclType:(NSString *)declType
                        declName:(NSString *)declName
                            body:(NSString *)body
               sourceVirtualPath:(NSString *)sourceVirtualPath NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface UDDeclModel : NSObject {
    NSArray<UDDeclDefinition *> *_definitions;
}

@property (nonatomic, readonly, copy) NSArray<UDDeclDefinition *> *definitions;

- (instancetype)initWithDefinitions:(NSArray<UDDeclDefinition *> *)definitions NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<UDDeclDefinition *> *)definitionsOfType:(NSString *)declType;
- (nullable UDDeclDefinition *)definitionWithType:(NSString *)declType name:(NSString *)declName;
- (NSArray<UDDeclDefinition *> *)definitionsWithNameContaining:(NSString *)nameFragment;
- (NSArray<UDDeclDefinition *> *)definitionsFromSourceVirtualPath:(NSString *)sourceVirtualPath;

@end

@interface UDDeclParser : NSObject

- (NSArray<UDDeclDefinition *> *)parseDefinitionsFromText:(NSString *)text
                                         sourceVirtualPath:(NSString *)sourceVirtualPath
                                                     error:(NSError **)error;

- (NSString *)serializeDefinitions:(NSArray<UDDeclDefinition *> *)definitions;

@end

@protocol UDDeclPersistenceAdapter;

typedef NS_ENUM(NSInteger, UDIdTokenKind) {
    UDIdTokenKindEOF = 0,
    UDIdTokenKindIdentifier,
    UDIdTokenKindString,
    UDIdTokenKindPunctuation,
};

@interface UDIdToken : NSObject

@property (nonatomic, assign) UDIdTokenKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) NSUInteger start;
@property (nonatomic, assign) NSUInteger end;

@end

@interface UDIdLexer : NSObject

- (instancetype)initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (UDIdToken *)nextToken;

@end

@interface UDIdParser : NSObject

- (instancetype)initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (UDIdToken *)peekToken;
- (UDIdToken *)readToken;
- (void)unreadToken:(UDIdToken *)token;
- (BOOL)expectPunctuation:(NSString *)punctuation;
- (void)skipUntilPunctuation:(NSString *)punctuation;

@end

@interface UDDeclManager : NSObject

- (UDDeclModel *)buildDeclModelFromAssetIndex:(UDAssetIndex *)assetIndex
                           persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                         error:(NSError **)error;

- (UDDeclModel *)rebuildDeclModelByApplyingWriteNotification:(NSNotification *)notification
                                              toExistingModel:(UDDeclModel *)existingModel
                                                   assetIndex:(UDAssetIndex *)assetIndex
                                           persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                                        error:(NSError **)error;

@end

@protocol UDDeclPersistenceAdapter <NSObject>

- (nullable NSString *)readDeclTextAtVirtualPath:(NSString *)virtualPath
                                           error:(NSError **)error;
- (BOOL)writeDeclText:(NSString *)text
         toVirtualPath:(NSString *)virtualPath
                 error:(NSError **)error;

@end

@interface UDVFSDeclPersistenceAdapter : NSObject <UDDeclPersistenceAdapter> {
    UDVirtualFileSystem *_virtualFileSystem;
}

@property (nonatomic, readonly, strong) UDVirtualFileSystem *virtualFileSystem;

- (instancetype)initWithVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

typedef NS_ENUM(NSInteger, UDDeclQuerySortField) {
    UDDeclQuerySortFieldType = 0,
    UDDeclQuerySortFieldName,
    UDDeclQuerySortFieldSourcePath,
};

@interface UDDeclQueryRequest : NSObject {
    NSString *_searchText;
    NSString *_declType;
    NSString *_sourceVirtualPath;
    UDDeclQuerySortField _sortField;
    BOOL _ascending;
    NSUInteger _maxResults;
}

@property (nonatomic, copy, nullable) NSString *searchText;
@property (nonatomic, copy, nullable) NSString *declType;
@property (nonatomic, copy, nullable) NSString *sourceVirtualPath;
@property (nonatomic) UDDeclQuerySortField sortField;
@property (nonatomic, getter=isAscending) BOOL ascending;
@property (nonatomic) NSUInteger maxResults;

@end

@interface UDDeclQueryService : NSObject

- (NSArray<UDDeclDefinition *> *)queryDefinitionsInModel:(UDDeclModel *)model
                                                  request:(nullable UDDeclQueryRequest *)request;

@end

@interface UDAssetIndexer : NSObject

- (UDAssetIndex *)buildIndexFromVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                            error:(NSError **)error;

- (UDAssetIndex *)rebuildIndexByApplyingWriteNotification:(NSNotification *)notification
                                           toExistingIndex:(UDAssetIndex *)existingIndex
                                         virtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                                     error:(NSError **)error;

- (UDDeclModel *)buildDeclModelFromAssetIndex:(UDAssetIndex *)assetIndex
                             virtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                         error:(NSError **)error;

- (UDDeclModel *)buildDeclModelFromAssetIndex:(UDAssetIndex *)assetIndex
                      persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                 error:(NSError **)error;

- (UDDeclModel *)rebuildDeclModelByApplyingWriteNotification:(NSNotification *)notification
                                              toExistingModel:(UDDeclModel *)existingModel
                                                   assetIndex:(UDAssetIndex *)assetIndex
                                            virtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                                        error:(NSError **)error;

- (UDDeclModel *)rebuildDeclModelByApplyingWriteNotification:(NSNotification *)notification
                                     toExistingModel:(UDDeclModel *)existingModel
                                         assetIndex:(UDAssetIndex *)assetIndex
                                  persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END