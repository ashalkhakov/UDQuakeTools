#import <AppKit/AppKit.h>

@class idDeclManager;

NS_ASSUME_NONNULL_BEGIN

/**
 * File > New Declaration…: DialogDeclNew's type, name and file, in a modal
 * window. The file follows the type and name (the type's folder, as
 * DialogDeclNew's file button starts in it) until it is typed in. Create
 * checks what DialogDeclNew's OK does: a name, a file, and no decl of that
 * type and name already.
 */
@interface UDNewDeclWindowController : NSWindowController

- (instancetype)initWithDeclManager:(idDeclManager *)declManager typeName:(nullable NSString *)typeName;

/// Runs the window modally: NSModalResponseOK when Create was pressed.
- (NSModalResponse)runModal;

/// The decl manager's type names, for the type popup.
@property (nonatomic, copy, readonly) NSArray<NSString *> *typeNames;
@property (nonatomic, copy) NSString *typeName;
@property (nonatomic, copy, nullable) NSString *declName;
@property (nonatomic, copy, nullable) NSString *fileName;

/// The file a decl of @a typeName named @a name goes in by default.
+ (NSString *)defaultFileNameForTypeName:(NSString *)typeName
                                    name:(NSString *)name
                             declManager:(idDeclManager *)declManager;

- (IBAction)create:(id)sender;
- (IBAction)cancel:(id)sender;

@end

NS_ASSUME_NONNULL_END
