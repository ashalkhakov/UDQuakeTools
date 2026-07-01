/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclModel.h — Decl definition model and query types.
 */

#import <Foundation/Foundation.h>

#import "UDDeclType.h"

NS_ASSUME_NONNULL_BEGIN

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
@property (nonatomic, readonly, nullable) UDDeclTypeDescriptor *typeDescriptor;

- (instancetype)initWithDeclType:(NSString *)declType
                        declName:(NSString *)declName
                            body:(NSString *)body
               sourceVirtualPath:(NSString *)sourceVirtualPath NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface UDDeclModel : NSObject {
    NSArray<UDDeclDefinition *> *_definitions;
    NSDictionary<NSString *, NSArray<UDDeclDefinition *> *> *_definitionsByType;
    NSDictionary<NSString *, UDDeclDefinition *> *_definitionsByTypeAndName;
    NSDictionary<NSString *, NSArray<UDDeclDefinition *> *> *_definitionsBySourceVirtualPath;
}

@property (nonatomic, readonly, copy) NSArray<UDDeclDefinition *> *definitions;

- (instancetype)initWithDefinitions:(NSArray<UDDeclDefinition *> *)definitions NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<UDDeclDefinition *> *)definitionsOfType:(NSString *)declType;
- (nullable UDDeclDefinition *)definitionWithType:(NSString *)declType name:(NSString *)declName;
- (NSArray<UDDeclDefinition *> *)definitionsWithNameContaining:(NSString *)nameFragment;
- (NSArray<UDDeclDefinition *> *)definitionsFromSourceVirtualPath:(NSString *)sourceVirtualPath;

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

NS_ASSUME_NONNULL_END
