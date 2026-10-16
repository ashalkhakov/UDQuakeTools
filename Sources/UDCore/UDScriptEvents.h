//
//  UDScriptEvents.h
//  UDCore
//
//  The script events a script editor offers, from script/doom_events.script:
//  each scriptEvent's name, its parameters and the comment above it. A port
//  of the tools' script editor (InitScriptEvents, and the GetScriptEvents,
//  GetFunctionParms and GetToolTip callbacks it gave its edit control).
//

#import <Foundation/Foundation.h>

@class idFileSystem;

NS_ASSUME_NONNULL_BEGIN

@interface UDScriptEvent : NSObject
@property (nonatomic, copy, readonly) NSString *name;
/// "<type> <name>( <parameters> )", as the declaration has them.
@property (nonatomic, copy, readonly) NSString *parms;
/// The // comment before the declaration, or "".
@property (nonatomic, copy, readonly) NSString *help;
@end

@interface UDScriptEvents : NSObject

/// The events script/doom_events.script declares, read through @a fileSystem;
/// none when there is no such file.
+ (instancetype)eventsFromFileSystem:(nullable idFileSystem *)fileSystem;

/// The events a text declares, in doom_events.script's form.
+ (instancetype)eventsFromText:(NSString *)text;

@property (nonatomic, copy, readonly) NSArray<UDScriptEvent *> *events;

/// What may follow "<objectName>.": every event's name, sorted (the events
/// are not told apart by the object they are called on).
- (NSArray<NSString *> *)membersOfObject:(NSString *)objectName;

/// The parameters to show after "<name>(", or nil.
- (nullable NSString *)functionParmsForName:(NSString *)name;

/// The tooltip for @a name: its help, then its parameters; or nil.
- (nullable NSString *)toolTipForName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
