/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiModel.h — Object model for Doom 3 / Quake 3 GUI editor documents.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class UDGuiScriptCommand;

@interface UDGuiProperty : NSObject

@property (nonatomic, readonly, copy) NSString *key;
@property (nonatomic, readonly, copy) NSString *value;

- (instancetype)initWithKey:(NSString *)key value:(NSString *)value NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

typedef NS_ENUM(NSInteger, UDGuiVariableDefinitionType) {
    UDGuiVariableDefinitionTypeFloat = 0,
    UDGuiVariableDefinitionTypeVec4,
};

typedef NS_ENUM(NSInteger, UDGuiEventHandlerType) {
    UDGuiEventHandlerTypeOnTime = 0,
    UDGuiEventHandlerTypeOnNamedEvent,
    UDGuiEventHandlerTypeOnAction,
    UDGuiEventHandlerTypeOnActionRelease,
    UDGuiEventHandlerTypeOnMouseEnter,
    UDGuiEventHandlerTypeOnMouseExit,
    UDGuiEventHandlerTypeOnActivate,
    UDGuiEventHandlerTypeOnDeactivate,
    UDGuiEventHandlerTypeOnEsc,
    UDGuiEventHandlerTypeOnEvent,
    UDGuiEventHandlerTypeOnTrigger,
    UDGuiEventHandlerTypeOnEnter,
    UDGuiEventHandlerTypeOnEnterRelease,
};

FOUNDATION_EXPORT NSString *UDGuiEventKeywordForType(UDGuiEventHandlerType type);
FOUNDATION_EXPORT BOOL UDGuiEventTypeFromKeyword(NSString *keyword, UDGuiEventHandlerType *outType);
FOUNDATION_EXPORT BOOL UDGuiIsScalarString(NSString *value);
FOUNDATION_EXPORT BOOL UDGuiIsRectString(NSString *value);
FOUNDATION_EXPORT BOOL UDGuiIsCommaSeparatedIntegerList(NSString *value);
FOUNDATION_EXPORT BOOL UDGuiIsCommaSeparatedAlignmentList(NSString *value);
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyShowTime;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyShowCoords;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyVisible;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyNoEvents;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyForceAspectWidth;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyForceAspectHeight;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyMatScaleX;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyMatScaleY;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyBorderSize;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyForeColor;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyHoverColor;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyBackColor;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyBorderColor;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyMatColor;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyNoWrap;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyShadow;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyTextAlign;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyTextAlignX;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyTextAlignY;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyShear;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyWantEnter;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyNaturalMatScale;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyNoClip;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyNoCursor;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyMenuGUI;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyModal;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyInvertRect;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyNameOverride;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyText;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyBackground;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyVarBackground;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyRunScript;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyPlay;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyComment;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyFont;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyRect;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyRotate;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyScale;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyTranslate;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyTextScale;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyTabStops;
FOUNDATION_EXPORT NSString *const UDGuiWindowPropertyTabAligns;
FOUNDATION_EXPORT UDGuiScriptCommand *UDGuiScriptCommandFromEditorValues(NSString *keyword,
                                                                          NSString *setVariable,
                                                                          NSString *setValue,
                                                                          NSString *setFocusWindow,
                                                                          NSString *resetTimeWindow,
                                                                          NSString *resetTimeValue,
                                                                          NSString *transitionVariable,
                                                                          NSString *transitionFrom,
                                                                          NSString *transitionTo,
                                                                          NSString *transitionTime,
                                                                          NSString *transitionAccel,
                                                                          NSString *transitionDecel,
                                                                          NSString *localSound,
                                                                          NSString *runScript,
                                                                          NSString *showCursor,
                                                                          NSString *fallbackArguments);

@interface UDGuiScriptCommand : NSObject

@property (nonatomic, readonly, copy) NSString *keyword;
@property (nonatomic, readonly, copy) NSString *arguments;

- (instancetype)initWithKeyword:(NSString *)keyword
                      arguments:(NSString *)arguments NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSString *)serializedStatement;
- (UDGuiScriptCommand *)deepCopy;

@end

@interface UDGuiSetCommand : UDGuiScriptCommand
@property (nonatomic, readonly, copy) NSString *variable;
@property (nonatomic, readonly, copy) NSString *valueExpression;
- (instancetype)initWithVariable:(NSString *)variable valueExpression:(NSString *)valueExpression;
@end

@interface UDGuiSetFocusCommand : UDGuiScriptCommand
@property (nonatomic, readonly, copy) NSString *windowName;
- (instancetype)initWithWindowName:(NSString *)windowName;
@end

@interface UDGuiResetTimeCommand : UDGuiScriptCommand
@property (nullable, nonatomic, readonly, copy) NSString *windowName;
@property (nullable, nonatomic, readonly, copy) NSString *timeExpression;
- (instancetype)initWithWindowName:(nullable NSString *)windowName timeExpression:(nullable NSString *)timeExpression;
@end

@interface UDGuiTransitionCommand : UDGuiScriptCommand
@property (nonatomic, readonly, copy) NSString *variable;
@property (nonatomic, readonly, copy) NSString *fromValue;
@property (nonatomic, readonly, copy) NSString *toValue;
@property (nonatomic, readonly, copy) NSString *timeExpression;
@property (nullable, nonatomic, readonly, copy) NSString *accelExpression;
@property (nullable, nonatomic, readonly, copy) NSString *decelExpression;
- (instancetype)initWithVariable:(NSString *)variable
                       fromValue:(NSString *)fromValue
                         toValue:(NSString *)toValue
                  timeExpression:(NSString *)timeExpression
                 accelExpression:(nullable NSString *)accelExpression
                 decelExpression:(nullable NSString *)decelExpression;
@end

@interface UDGuiSingleArgumentCommand : UDGuiScriptCommand
@property (nonatomic, readonly, copy) NSString *value;
- (instancetype)initWithKeyword:(NSString *)keyword value:(NSString *)value;
@end

@interface UDGuiExpression : NSObject <NSCopying>
- (NSString *)serializedString;
- (UDGuiExpression *)deepCopy;
@end

@interface UDGuiLiteralExpression : UDGuiExpression
@property (nonatomic, readonly, copy) NSString *value;
@property (nonatomic, readonly, assign) BOOL isQuoted;
- (instancetype)initWithValue:(NSString *)value isQuoted:(BOOL)isQuoted;
@end

@interface UDGuiVariableExpression : UDGuiExpression
@property (nonatomic, readonly, copy) NSString *name;
- (instancetype)initWithName:(NSString *)name;
@end

@interface UDGuiParenthesizedExpression : UDGuiExpression
@property (nonatomic, readonly, strong) UDGuiExpression *expression;
- (instancetype)initWithExpression:(UDGuiExpression *)expression;
@end

@interface UDGuiUnaryExpression : UDGuiExpression
@property (nonatomic, readonly, copy) NSString *operatorString;
@property (nonatomic, readonly, strong) UDGuiExpression *operand;
- (instancetype)initWithOperator:(NSString *)operatorString operand:(UDGuiExpression *)operand;
@end

@interface UDGuiBinaryExpression : UDGuiExpression
@property (nonatomic, readonly, strong) UDGuiExpression *left;
@property (nonatomic, readonly, copy) NSString *operatorString;
@property (nonatomic, readonly, strong) UDGuiExpression *right;
- (instancetype)initWithLeft:(UDGuiExpression *)left operator:(NSString *)operatorString right:(UDGuiExpression *)right;
@end

@interface UDGuiIfBranch : NSObject <NSCopying>
@property (nullable, nonatomic, readonly, strong) UDGuiExpression *condition;
@property (nonatomic, readonly, copy) NSArray<UDGuiScriptCommand *> *commands;
- (instancetype)initWithCondition:(nullable UDGuiExpression *)condition commands:(NSArray<UDGuiScriptCommand *> *)commands;
- (UDGuiIfBranch *)deepCopy;
@end

@interface UDGuiIfCommand : UDGuiScriptCommand
@property (nonatomic, readonly, copy) NSArray<UDGuiIfBranch *> *branches;
- (instancetype)initWithBranches:(NSArray<UDGuiIfBranch *> *)branches;
@end

@interface UDGuiEventHandler : NSObject

@property (nonatomic, readonly, assign) UDGuiEventHandlerType type;
@property (nonatomic, readonly, copy) NSArray<UDGuiScriptCommand *> *commands;

- (instancetype)initWithType:(UDGuiEventHandlerType)type NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSString *)eventKeyword;
- (nullable NSString *)eventQualifier;

- (void)addCommand:(UDGuiScriptCommand *)command;
- (void)insertCommand:(UDGuiScriptCommand *)command atIndex:(NSUInteger)index;
- (void)replaceCommandAtIndex:(NSUInteger)index withCommand:(UDGuiScriptCommand *)command;
- (void)removeCommandAtIndex:(NSUInteger)index;

- (UDGuiEventHandler *)deepCopy;

@end

@interface UDGuiSimpleEventHandler : UDGuiEventHandler
- (instancetype)initWithType:(UDGuiEventHandlerType)type;
@end

@interface UDGuiTimedEventHandler : UDGuiEventHandler
@property (nonatomic, copy) NSString *timeExpression;
- (instancetype)initWithTimeExpression:(NSString *)timeExpression;
@end

@interface UDGuiNamedEventHandler : UDGuiEventHandler
@property (nonatomic, copy) NSString *eventName;
- (instancetype)initWithEventName:(NSString *)eventName;
@end

@interface UDGuiVariableDefinition : NSObject

@property (nonatomic, readonly, assign) UDGuiVariableDefinitionType type;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *value;

- (instancetype)initWithType:(UDGuiVariableDefinitionType)type
                        name:(NSString *)name
                       value:(NSString *)value NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSString *)keyword;

@end

@interface UDGuiWindowNode : NSObject

@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *name;
@property (nullable, nonatomic, assign) UDGuiWindowNode *parent;
@property (nonatomic, readonly, copy) NSArray<UDGuiProperty *> *properties;
@property (nonatomic, readonly, copy) NSArray<UDGuiVariableDefinition *> *variableDefinitions;
@property (nonatomic, readonly, copy) NSArray<UDGuiEventHandler *> *eventHandlers;
@property (nonatomic, readonly, copy) NSArray<UDGuiWindowNode *> *children;
@property (nonatomic, assign) BOOL showTime;
@property (nonatomic, assign) BOOL showCoords;
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, assign) BOOL noEvents;
@property (nonatomic, assign) double forceAspectWidth;
@property (nonatomic, assign) double forceAspectHeight;
@property (nonatomic, assign) double matScaleX;
@property (nonatomic, assign) double matScaleY;
@property (nonatomic, assign) double borderSize;
@property (nonatomic, copy) NSString *foreColor;
@property (nonatomic, copy) NSString *hoverColor;
@property (nonatomic, copy) NSString *backColor;
@property (nonatomic, copy) NSString *borderColor;
@property (nonatomic, copy) NSString *matColor;
@property (nonatomic, copy, nullable) NSString *scale;
@property (nonatomic, copy, nullable) NSString *translate;
@property (nonatomic, assign) BOOL noWrap;
@property (nonatomic, assign) BOOL shadow;
@property (nonatomic, assign) double textScale;
@property (nonatomic, assign) NSInteger textAlign;
@property (nonatomic, assign) double textAlignX;
@property (nonatomic, assign) double textAlignY;
@property (nonatomic, copy) NSString *shear;
@property (nonatomic, assign) BOOL wantEnter;
@property (nonatomic, assign) BOOL naturalMatScale;
@property (nonatomic, assign) BOOL noClip;
@property (nonatomic, assign) BOOL noCursor;
@property (nonatomic, assign) BOOL menuGUI;
@property (nonatomic, assign) BOOL modal;
@property (nonatomic, assign) BOOL invertRect;
@property (nonatomic, copy) NSString *nameOverride;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *background;
@property (nonatomic, copy, nullable) NSString *varBackground;
@property (nonatomic, copy, nullable) NSString *runScript;
@property (nonatomic, copy, nullable) NSString *play;
@property (nonatomic, copy, nullable) NSString *comment;
@property (nonatomic, copy, nullable) NSString *font;

- (instancetype)initWithClassName:(NSString *)className
                              name:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)windowNodeWithClassName:(NSString *)className
                                    name:(NSString *)name;

- (nullable UDGuiProperty *)propertyForKey:(NSString *)key;
- (void)setPropertyValue:(NSString *)value forKey:(NSString *)key;
- (void)removePropertyForKey:(NSString *)key;

- (nullable NSString *)stringPropertyForKey:(NSString *)key;
- (nullable NSNumber *)numberPropertyForKey:(NSString *)key;
- (BOOL)boolPropertyForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
- (void)setNumberPropertyValue:(double)value forKey:(NSString *)key;
- (void)setBoolPropertyValue:(BOOL)value forKey:(NSString *)key;

- (void)addVariableDefinition:(UDGuiVariableDefinition *)definition;
- (void)insertVariableDefinition:(UDGuiVariableDefinition *)definition atIndex:(NSUInteger)index;
- (void)replaceVariableDefinitionAtIndex:(NSUInteger)index withDefinition:(UDGuiVariableDefinition *)definition;
- (void)removeVariableDefinitionAtIndex:(NSUInteger)index;

- (void)addEventHandler:(UDGuiEventHandler *)eventHandler;
- (void)insertEventHandler:(UDGuiEventHandler *)eventHandler atIndex:(NSUInteger)index;
- (void)replaceEventHandlerAtIndex:(NSUInteger)index withEventHandler:(UDGuiEventHandler *)eventHandler;
- (void)removeEventHandlerAtIndex:(NSUInteger)index;

- (void)addChild:(UDGuiWindowNode *)child;
- (void)insertChild:(UDGuiWindowNode *)child atIndex:(NSUInteger)index;
- (void)removeChild:(UDGuiWindowNode *)child;
- (NSUInteger)indexOfChild:(UDGuiWindowNode *)child;

- (UDGuiWindowNode *)deepCopy;

@end

@interface UDEditDefWindowNode : UDGuiWindowNode
@property (nonatomic, copy, nullable) NSString *cvar;
@property (nonatomic, assign) NSInteger maxChars;
@property (nonatomic, assign) BOOL numeric;
@property (nonatomic, assign) BOOL wrap;
@property (nonatomic, assign) BOOL readOnly;
@property (nonatomic, assign) BOOL forceScroll;
@property (nonatomic, copy, nullable) NSString *source;
@property (nonatomic, assign) BOOL password;
@property (nonatomic, assign) BOOL liveUpdate;
@property (nonatomic, copy, nullable) NSString *cvarGroup;
@end

@interface UDChoiceDefWindowNode : UDGuiWindowNode
@property (nonatomic, assign) NSInteger choiceType;
@property (nonatomic, copy, nullable) NSString *gui;
@property (nonatomic, copy, nullable) NSString *cvar;
@property (nonatomic, copy, nullable) NSString *choices;
@property (nonatomic, copy, nullable) NSString *values;
@property (nonatomic, assign) NSInteger currentChoice;
@property (nonatomic, assign) BOOL liveUpdate;
@property (nonatomic, copy, nullable) NSString *cvarGroup;
@end

@interface UDSliderDefWindowNode : UDGuiWindowNode
@property (nonatomic, copy, nullable) NSString *cvar;
@property (nonatomic, assign) double low;
@property (nonatomic, assign) double high;
@property (nonatomic, assign) double stepSize;
@property (nonatomic, assign) BOOL vertical;
@property (nonatomic, assign) BOOL scrollBar;
@property (nonatomic, copy, nullable) NSString *thumbShader;
@property (nonatomic, assign) BOOL liveUpdate;
@property (nonatomic, copy, nullable) NSString *cvarGroup;
@end

@interface UDBindDefWindowNode : UDGuiWindowNode
@property (nonatomic, copy, nullable) NSString *bind;
@end

@interface UDRenderDefWindowNode : UDGuiWindowNode
@property (nonatomic, copy, nullable) NSString *model;
@property (nonatomic, copy, nullable) NSString *anim;
@property (nonatomic, copy, nullable) NSString *animClass;
@property (nonatomic, copy, nullable) NSString *lightOrigin;
@property (nonatomic, copy, nullable) NSString *lightColor;
@property (nonatomic, copy, nullable) NSString *modelOrigin;
@property (nonatomic, copy, nullable) NSString *modelRotate;
@property (nonatomic, copy, nullable) NSString *viewOffset;
@property (nonatomic, assign) BOOL needsRender;
@end

@interface UDListDefWindowNode : UDGuiWindowNode
@property (nonatomic, assign) BOOL horizontal;
@property (nonatomic, copy, nullable) NSString *listName;
@property (nonatomic, copy, nullable) NSString *tabStops;
@property (nonatomic, copy, nullable) NSString *tabAligns;
@property (nonatomic, assign) BOOL multipleSelection;
@end

@interface UDGuiDocument : NSObject

@property (nonatomic, copy) NSString *sourceVirtualPath;
@property (nonatomic, readonly, copy) NSArray<UDGuiWindowNode *> *rootWindows;

- (instancetype)initWithSourceVirtualPath:(NSString *)sourceVirtualPath NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addRootWindow:(UDGuiWindowNode *)window;
- (void)insertRootWindow:(UDGuiWindowNode *)window atIndex:(NSUInteger)index;
- (void)removeRootWindow:(UDGuiWindowNode *)window;
- (NSUInteger)indexOfRootWindow:(UDGuiWindowNode *)window;

@end

NS_ASSUME_NONNULL_END
