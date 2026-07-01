/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEditorService.h — GUI editing operations with undo/redo support.
 */

#import <Foundation/Foundation.h>

#import "UDGuiModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiDocumentCodec : NSObject

- (nullable UDGuiDocument *)parseDocumentFromText:(NSString *)text
                                sourceVirtualPath:(NSString *)sourceVirtualPath
                                            error:(NSError **)error;

- (nullable NSString *)serializeDocument:(UDGuiDocument *)document error:(NSError **)error;

@end

@interface UDGuiEditorService : NSObject

@property (nonatomic, readonly, strong) UDGuiDocument *document;
@property (nonatomic, readonly, strong) NSUndoManager *undoManager;

- (instancetype)initWithDocument:(UDGuiDocument *)document
                     undoManager:(nullable NSUndoManager *)undoManager NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)replaceDocument:(UDGuiDocument *)document;

- (void)updatePropertyForWindow:(UDGuiWindowNode *)window
                            key:(NSString *)key
                          value:(NSString *)value;

- (void)updateWindow:(UDGuiWindowNode *)window className:(NSString *)className;

- (void)updateWindow:(UDGuiWindowNode *)window name:(NSString *)name;

- (void)renamePropertyForWindow:(UDGuiWindowNode *)window
                         fromKey:(NSString *)oldKey
                           toKey:(NSString *)newKey
                           value:(NSString *)value;

- (void)removePropertyForWindow:(UDGuiWindowNode *)window
                            key:(NSString *)key;

- (void)addWindow:(UDGuiWindowNode *)window
         toParent:(nullable UDGuiWindowNode *)parent
          atIndex:(NSUInteger)index;

- (void)removeWindow:(UDGuiWindowNode *)window;

- (void)moveWindow:(UDGuiWindowNode *)window
       toNewParent:(nullable UDGuiWindowNode *)newParent
            atIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
