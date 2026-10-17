/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDReferencePicker.h — what a field names, chosen from a list: a sheet
 * (modal on GNUstep) with the candidates in a table, filtered as a name is
 * typed (the names containing it, in any case), the current one chosen.
 * XFormsKit's palette panel's filter, in a XIB (UDReferencePicker.xib).
 * Double-click or OK chooses; Escape or Cancel does not.
 */

#import <Cocoa/Cocoa.h>

@class UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

/// What a field's picker chooses from.
typedef NS_ENUM(NSInteger, UDReferenceKind) {
    UDReferenceDecls,       // the decls of a type
    UDReferenceMaterials,   // material decls, and images (what a material may be)
    UDReferenceImages,      // image files, with their extensions
    UDReferenceModels,      // model files
    UDReferenceEntityModels,// what an entity's model names: a modelDef, or a model file
    UDReferenceVideos,      // cinematics (.roq)
    UDReferenceGuis,        // GUI files
    UDReferenceSounds,      // sound files (.wav, .ogg)
    UDReferenceCubeMaps,    // cube maps' names (name_px.tga …, name_forward.tga …)
    UDReferencePrograms,    // ARB programs, by their names under glprogs/
    UDReferenceNames,       // names the editor gives (joints, bodies, actions)
};

/// A field that names something, and its picker (the "…" beside it).
@interface UDReferenceField : NSObject
+ (instancetype)fieldTitled:(NSString *)title key:(NSString *)key controller:(id)controller kind:(UDReferenceKind)kind;
@property (nonatomic, copy) NSString *title;
/// The value set: selection.<key> of the controller (an object or array
/// controller), as the field's binding sets it.
@property (nonatomic, copy) NSString *key;
@property (nonatomic, weak) id controller;
@property (nonatomic) UDReferenceKind kind;
/// For UDReferenceDecls: the decls' type (a declType_t).
@property (nonatomic) int declType;
/// For UDReferenceNames: the names, and what each is.
@property (nonatomic, copy, nullable) NSArray<NSString *> *names;
@property (nonatomic, copy, nullable) NSArray<NSString *> *details;
@end


@interface UDReferencePicker : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

/// @a names to choose from (each with what it is, in @a details, if
/// given), @a current chosen at first.
- (instancetype)initWithTitle:(NSString *)title names:(NSArray<NSString *> *)names
                      details:(nullable NSArray<NSString *> *)details current:(nullable NSString *)current;

/// The sheet over @a window; on OK, @a action sent to @a target (the sender
/// the picker, its chosenName the name).
- (void)beginSheetForWindow:(NSWindow *)window target:(id)target action:(SEL)action;

@property (nonatomic, copy, readonly, nullable) NSString *chosenName;

/// What a picker for @a field offers in @a workspace: names, sorted, and
/// what each is in @a details (a decl's file, "image", …).
+ (NSArray<NSString *> *)namesFor:(UDReferenceField *)field workspace:(UDWorkspace *)workspace
                          details:(NSMutableArray<NSString *> *)details;
/// The filter as typed; the names shown (its rows).
@property (nonatomic, copy, readonly) NSArray<NSString *> *shownNames;

@property (weak) IBOutlet NSTextField *titleLabel;
@property (weak) IBOutlet NSTextField *filterField;
@property (weak) IBOutlet NSTableView *table;
@property (weak) IBOutlet NSTextField *countLabel;
@property (weak) IBOutlet NSButton *okButton;
- (IBAction)filterChanged:(nullable id)sender;
- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
