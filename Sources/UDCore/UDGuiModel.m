/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiModel.m — Object model for GUI editor documents.
 */

#import "UDGuiModel.h"

static NSString *const UDGuiValidationErrorDomain = @"com.udquake.validation.gui";
NSString *const UDGuiWindowPropertyShowTime = @"showTime";
NSString *const UDGuiWindowPropertyShowCoords = @"showCoords";
NSString *const UDGuiWindowPropertyVisible = @"visible";
NSString *const UDGuiWindowPropertyNoEvents = @"noEvents";
NSString *const UDGuiWindowPropertyForceAspectWidth = @"forceAspectWidth";
NSString *const UDGuiWindowPropertyForceAspectHeight = @"forceAspectHeight";
NSString *const UDGuiWindowPropertyMatScaleX = @"matScaleX";
NSString *const UDGuiWindowPropertyMatScaleY = @"matScaleY";
NSString *const UDGuiWindowPropertyBorderSize = @"borderSize";
NSString *const UDGuiWindowPropertyForeColor = @"foreColor";
NSString *const UDGuiWindowPropertyHoverColor = @"hoverColor";
NSString *const UDGuiWindowPropertyBackColor = @"backColor";
NSString *const UDGuiWindowPropertyBorderColor = @"borderColor";
NSString *const UDGuiWindowPropertyMatColor = @"matColor";
NSString *const UDGuiWindowPropertyNoWrap = @"noWrap";
NSString *const UDGuiWindowPropertyShadow = @"shadow";
NSString *const UDGuiWindowPropertyTextAlign = @"textAlign";
NSString *const UDGuiWindowPropertyTextAlignX = @"textAlignX";
NSString *const UDGuiWindowPropertyTextAlignY = @"textAlignY";
NSString *const UDGuiWindowPropertyShear = @"shear";
NSString *const UDGuiWindowPropertyWantEnter = @"wantEnter";
NSString *const UDGuiWindowPropertyNaturalMatScale = @"naturalMatScale";
NSString *const UDGuiWindowPropertyNoClip = @"noClip";
NSString *const UDGuiWindowPropertyNoCursor = @"noCursor";
NSString *const UDGuiWindowPropertyMenuGUI = @"menuGUI";
NSString *const UDGuiWindowPropertyModal = @"modal";
NSString *const UDGuiWindowPropertyInvertRect = @"invertRect";
NSString *const UDGuiWindowPropertyNameOverride = @"nameOverride";
NSString *const UDGuiWindowPropertyText = @"text";
NSString *const UDGuiWindowPropertyBackground = @"background";
NSString *const UDGuiWindowPropertyVarBackground = @"varBackground";
NSString *const UDGuiWindowPropertyRunScript = @"runScript";
NSString *const UDGuiWindowPropertyPlay = @"play";
NSString *const UDGuiWindowPropertyComment = @"comment";
NSString *const UDGuiWindowPropertyFont = @"font";
NSString *const UDGuiWindowPropertyRect = @"rect";
NSString *const UDGuiWindowPropertyRotate = @"rotate";
NSString *const UDGuiWindowPropertyScale = @"scale";
NSString *const UDGuiWindowPropertyTranslate = @"translate";
NSString *const UDGuiWindowPropertyTextScale = @"textScale";
NSString *const UDGuiWindowPropertyTabStops = @"tabstops";
NSString *const UDGuiWindowPropertyTabAligns = @"tabaligns";

static NSString *UDGuiTrimmedString(NSString *value) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

UDGuiScriptCommand *UDGuiScriptCommandFromEditorValues(NSString *keyword,
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
                                                        NSString *fallbackArguments) {
    NSString *canonicalKeyword = keyword ?: @"";
    NSString *lower = canonicalKeyword.lowercaseString;

    if ([lower isEqualToString:@"set"]) {
        NSString *variable = UDGuiTrimmedString(setVariable ?: @"");
        NSString *value = UDGuiTrimmedString(setValue ?: @"");
        if (variable.length == 0) {
            NSString *arguments = [NSString stringWithFormat:@"%@ %@", variable, value];
            return [[UDGuiScriptCommand alloc] initWithKeyword:canonicalKeyword arguments:UDGuiTrimmedString(arguments)];
        }
        return [[UDGuiSetCommand alloc] initWithVariable:variable valueExpression:value ?: @""];
    }

    if ([lower isEqualToString:@"setfocus"]) {
        NSString *windowName = UDGuiTrimmedString(setFocusWindow ?: @"");
        if (windowName.length == 0) {
            return [[UDGuiScriptCommand alloc] initWithKeyword:canonicalKeyword arguments:@""];
        }
        return [[UDGuiSetFocusCommand alloc] initWithWindowName:windowName];
    }

    if ([lower isEqualToString:@"resettime"]) {
        return [[UDGuiResetTimeCommand alloc] initWithWindowName:UDGuiTrimmedString(resetTimeWindow ?: @"")
                                                   timeExpression:UDGuiTrimmedString(resetTimeValue ?: @"")];
    }

    if ([lower isEqualToString:@"transition"]) {
        NSString *variable = UDGuiTrimmedString(transitionVariable ?: @"");
        NSString *fromValue = UDGuiTrimmedString(transitionFrom ?: @"");
        NSString *toValue = UDGuiTrimmedString(transitionTo ?: @"");
        NSString *timeExpression = UDGuiTrimmedString(transitionTime ?: @"");
        NSString *accel = UDGuiTrimmedString(transitionAccel ?: @"");
        NSString *decel = UDGuiTrimmedString(transitionDecel ?: @"");

        if (variable.length > 0 && fromValue.length > 0 && toValue.length > 0 && timeExpression.length > 0) {
            return [[UDGuiTransitionCommand alloc] initWithVariable:variable
                                                           fromValue:fromValue
                                                             toValue:toValue
                                                      timeExpression:timeExpression
                                                     accelExpression:(accel.length > 0 ? accel : nil)
                                                     decelExpression:(decel.length > 0 ? decel : nil)];
        }

        NSString *arguments = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", variable, fromValue, toValue, timeExpression, accel, decel];
        return [[UDGuiScriptCommand alloc] initWithKeyword:canonicalKeyword arguments:UDGuiTrimmedString(arguments)];
    }

    if ([lower isEqualToString:@"localsound"] || [lower isEqualToString:@"runscript"] || [lower isEqualToString:@"showcursor"]) {
        NSString *value = @"";
        if ([lower isEqualToString:@"localsound"]) {
            value = UDGuiTrimmedString(localSound ?: @"");
        } else if ([lower isEqualToString:@"runscript"]) {
            value = UDGuiTrimmedString(runScript ?: @"");
        } else {
            value = UDGuiTrimmedString(showCursor ?: @"");
        }
        return [[UDGuiSingleArgumentCommand alloc] initWithKeyword:canonicalKeyword value:value ?: @""];
    }

    if ([lower isEqualToString:@"evalregs"] || [lower isEqualToString:@"resetcinematics"] || [lower isEqualToString:@"endgame"]) {
        return [[UDGuiScriptCommand alloc] initWithKeyword:canonicalKeyword arguments:@""];
    }

    return [[UDGuiScriptCommand alloc] initWithKeyword:canonicalKeyword
                                             arguments:UDGuiTrimmedString(fallbackArguments ?: @"") ?: @""];
}

NSString *UDGuiEventKeywordForType(UDGuiEventHandlerType type) {
    switch (type) {
        case UDGuiEventHandlerTypeOnTime: return @"onTime";
        case UDGuiEventHandlerTypeOnNamedEvent: return @"onNamedEvent";
        case UDGuiEventHandlerTypeOnAction: return @"onAction";
        case UDGuiEventHandlerTypeOnActionRelease: return @"onActionRelease";
        case UDGuiEventHandlerTypeOnMouseEnter: return @"onMouseEnter";
        case UDGuiEventHandlerTypeOnMouseExit: return @"onMouseExit";
        case UDGuiEventHandlerTypeOnActivate: return @"onActivate";
        case UDGuiEventHandlerTypeOnDeactivate: return @"onDeactivate";
        case UDGuiEventHandlerTypeOnEsc: return @"onEsc";
        case UDGuiEventHandlerTypeOnEvent: return @"onEvent";
        case UDGuiEventHandlerTypeOnTrigger: return @"onTrigger";
        case UDGuiEventHandlerTypeOnEnter: return @"onEnter";
        case UDGuiEventHandlerTypeOnEnterRelease: return @"onEnterRelease";
    }
}

BOOL UDGuiEventTypeFromKeyword(NSString *keyword, UDGuiEventHandlerType *outType) {
    NSString *lower = keyword.lowercaseString;
    if ([lower isEqualToString:@"ontime"]) { *outType = UDGuiEventHandlerTypeOnTime; return YES; }
    if ([lower isEqualToString:@"onnamedevent"]) { *outType = UDGuiEventHandlerTypeOnNamedEvent; return YES; }
    if ([lower isEqualToString:@"onaction"]) { *outType = UDGuiEventHandlerTypeOnAction; return YES; }
    if ([lower isEqualToString:@"onactionrelease"]) { *outType = UDGuiEventHandlerTypeOnActionRelease; return YES; }
    if ([lower isEqualToString:@"onmouseenter"]) { *outType = UDGuiEventHandlerTypeOnMouseEnter; return YES; }
    if ([lower isEqualToString:@"onmouseexit"]) { *outType = UDGuiEventHandlerTypeOnMouseExit; return YES; }
    if ([lower isEqualToString:@"onactivate"]) { *outType = UDGuiEventHandlerTypeOnActivate; return YES; }
    if ([lower isEqualToString:@"ondeactivate"]) { *outType = UDGuiEventHandlerTypeOnDeactivate; return YES; }
    if ([lower isEqualToString:@"onesc"]) { *outType = UDGuiEventHandlerTypeOnEsc; return YES; }
    if ([lower isEqualToString:@"onevent"]) { *outType = UDGuiEventHandlerTypeOnEvent; return YES; }
    if ([lower isEqualToString:@"ontrigger"]) { *outType = UDGuiEventHandlerTypeOnTrigger; return YES; }
    if ([lower isEqualToString:@"onenter"]) { *outType = UDGuiEventHandlerTypeOnEnter; return YES; }
    if ([lower isEqualToString:@"onenterrelease"]) { *outType = UDGuiEventHandlerTypeOnEnterRelease; return YES; }
    return NO;
}

BOOL UDGuiIsScalarString(NSString *value) {
    if (value.length == 0) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    double parsed = 0.0;
    return [scanner scanDouble:&parsed] && scanner.isAtEnd;
}

BOOL UDGuiIsRectString(NSString *value) {
    NSString *normalized = [[value stringByReplacingOccurrencesOfString:@"," withString:@" "]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (normalized.length == 0) {
        return NO;
    }

    NSArray<NSString *> *parts = [normalized componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSUInteger count = 0;
    for (NSString *part in parts) {
        if (part.length == 0) {
            continue;
        }
        if (!UDGuiIsScalarString(part)) {
            return NO;
        }
        count++;
    }
    return count == 4;
}

BOOL UDGuiIsCommaSeparatedIntegerList(NSString *value) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return NO;
    }

    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@","];
    for (NSString *raw in parts) {
        NSString *part = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (part.length == 0) {
            return NO;
        }
        NSScanner *scanner = [NSScanner scannerWithString:part];
        NSInteger parsed = 0;
        if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
            return NO;
        }
    }
    return YES;
}

BOOL UDGuiIsCommaSeparatedAlignmentList(NSString *value) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return NO;
    }

    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@","];
    for (NSString *raw in parts) {
        NSString *part = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (part.length == 0) {
            return NO;
        }
        if (![part isEqualToString:@"0"] && ![part isEqualToString:@"1"] && ![part isEqualToString:@"2"]) {
            return NO;
        }
    }
    return YES;
}

@interface UDGuiWindowNode ()
@property (nonatomic, strong) NSMutableArray<UDGuiProperty *> *mutableProperties;
@property (nonatomic, strong) NSMutableArray<UDGuiVariableDefinition *> *mutableVariableDefinitions;
@property (nonatomic, strong) NSMutableArray<UDGuiEventHandler *> *mutableEventHandlers;
@property (nonatomic, strong) NSMutableArray<UDGuiWindowNode *> *mutableChildren;
@end

@interface UDGuiDocument ()
@property (nonatomic, strong) NSMutableArray<UDGuiWindowNode *> *mutableRootWindows;
@end

@implementation UDGuiProperty

@synthesize key = _key;
@synthesize value = _value;

- (instancetype)initWithKey:(NSString *)key value:(NSString *)value {
    NSParameterAssert(key.length > 0);
    NSParameterAssert(value != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _key = [key copy];
    _value = [value copy];
    return self;
}

@end

@implementation UDGuiVariableDefinition

@synthesize type = _type;
@synthesize name = _name;
@synthesize value = _value;

- (instancetype)initWithType:(UDGuiVariableDefinitionType)type
                        name:(NSString *)name
                       value:(NSString *)value {
    NSParameterAssert(name != nil);
    NSParameterAssert(value != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _type = type;
    _name = [name copy];
    _value = [value copy];
    return self;
}

- (NSString *)keyword {
    return self.type == UDGuiVariableDefinitionTypeVec4 ? @"definevec4" : @"definefloat";
}

@end

@implementation UDGuiScriptCommand

@synthesize keyword = _keyword;
@synthesize arguments = _arguments;

- (instancetype)initWithKeyword:(NSString *)keyword arguments:(NSString *)arguments {
    NSParameterAssert(keyword.length > 0);
    NSParameterAssert(arguments != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _keyword = [keyword copy];
    _arguments = [arguments copy];
    return self;
}

- (NSString *)serializedStatement {
    NSString *trimmedArguments = [self.arguments stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmedArguments.length > 0 ? [NSString stringWithFormat:@"%@ %@", self.keyword, trimmedArguments] : self.keyword;
}

- (UDGuiScriptCommand *)deepCopy {
    return [[[self class] alloc] initWithKeyword:self.keyword arguments:self.arguments];
}

@end

@implementation UDGuiSetCommand

- (instancetype)initWithVariable:(NSString *)variable valueExpression:(NSString *)valueExpression {
    NSParameterAssert(variable.length > 0);
    NSParameterAssert(valueExpression != nil);

    NSString *arguments = valueExpression.length > 0 ? [NSString stringWithFormat:@"%@ %@", variable, valueExpression] : variable;
    self = [super initWithKeyword:@"set" arguments:arguments];
    if (!self) {
        return nil;
    }

    _variable = [variable copy];
    _valueExpression = [valueExpression copy];
    return self;
}

- (UDGuiScriptCommand *)deepCopy {
    return [[UDGuiSetCommand alloc] initWithVariable:self.variable valueExpression:self.valueExpression];
}

@end

@implementation UDGuiSetFocusCommand

- (instancetype)initWithWindowName:(NSString *)windowName {
    NSParameterAssert(windowName.length > 0);

    self = [super initWithKeyword:@"setFocus" arguments:windowName];
    if (!self) {
        return nil;
    }
    _windowName = [windowName copy];
    return self;
}

- (UDGuiScriptCommand *)deepCopy {
    return [[UDGuiSetFocusCommand alloc] initWithWindowName:self.windowName];
}

@end

@implementation UDGuiResetTimeCommand

- (instancetype)initWithWindowName:(nullable NSString *)windowName timeExpression:(nullable NSString *)timeExpression {
    NSString *windowPart = [windowName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *timePart = [timeExpression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (windowPart.length > 0) {
        [parts addObject:windowPart];
    }
    if (timePart.length > 0) {
        [parts addObject:timePart];
    }

    self = [super initWithKeyword:@"resetTime" arguments:[parts componentsJoinedByString:@" "]];
    if (!self) {
        return nil;
    }

    _windowName = windowPart.length > 0 ? [windowPart copy] : nil;
    _timeExpression = timePart.length > 0 ? [timePart copy] : nil;
    return self;
}

- (UDGuiScriptCommand *)deepCopy {
    return [[UDGuiResetTimeCommand alloc] initWithWindowName:self.windowName timeExpression:self.timeExpression];
}

@end

@implementation UDGuiTransitionCommand

- (instancetype)initWithVariable:(NSString *)variable
                       fromValue:(NSString *)fromValue
                         toValue:(NSString *)toValue
                  timeExpression:(NSString *)timeExpression
                 accelExpression:(nullable NSString *)accelExpression
                 decelExpression:(nullable NSString *)decelExpression {
    NSParameterAssert(variable.length > 0);
    NSParameterAssert(fromValue.length > 0);
    NSParameterAssert(toValue.length > 0);
    NSParameterAssert(timeExpression.length > 0);

    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObjects:variable, fromValue, toValue, timeExpression, nil];
    if (accelExpression.length > 0) {
        [parts addObject:accelExpression];
    }
    if (decelExpression.length > 0) {
        [parts addObject:decelExpression];
    }

    self = [super initWithKeyword:@"transition" arguments:[parts componentsJoinedByString:@" "]];
    if (!self) {
        return nil;
    }

    _variable = [variable copy];
    _fromValue = [fromValue copy];
    _toValue = [toValue copy];
    _timeExpression = [timeExpression copy];
    _accelExpression = accelExpression.length > 0 ? [accelExpression copy] : nil;
    _decelExpression = decelExpression.length > 0 ? [decelExpression copy] : nil;
    return self;
}

- (UDGuiScriptCommand *)deepCopy {
    return [[UDGuiTransitionCommand alloc] initWithVariable:self.variable
                                                 fromValue:self.fromValue
                                                   toValue:self.toValue
                                            timeExpression:self.timeExpression
                                           accelExpression:self.accelExpression
                                           decelExpression:self.decelExpression];
}

@end

@implementation UDGuiSingleArgumentCommand

- (instancetype)initWithKeyword:(NSString *)keyword value:(NSString *)value {
    NSParameterAssert(value != nil);

    self = [super initWithKeyword:keyword arguments:value];
    if (!self) {
        return nil;
    }
    _value = [value copy];
    return self;
}

- (UDGuiScriptCommand *)deepCopy {
    return [[UDGuiSingleArgumentCommand alloc] initWithKeyword:self.keyword value:self.value];
}

@end

@implementation UDGuiEventHandler {
    NSMutableArray<UDGuiScriptCommand *> *_mutableCommands;
}

@synthesize type = _type;

- (instancetype)initWithType:(UDGuiEventHandlerType)type {
    self = [super init];
    if (!self) {
        return nil;
    }

    _type = type;
    _mutableCommands = [NSMutableArray array];
    return self;
}

- (NSArray<UDGuiScriptCommand *> *)commands {
    return [_mutableCommands copy];
}

- (NSString *)eventKeyword {
    switch (self.type) {
        case UDGuiEventHandlerTypeOnTime: return @"onTime";
        case UDGuiEventHandlerTypeOnNamedEvent: return @"onNamedEvent";
        case UDGuiEventHandlerTypeOnAction: return @"onAction";
        case UDGuiEventHandlerTypeOnActionRelease: return @"onActionRelease";
        case UDGuiEventHandlerTypeOnMouseEnter: return @"onMouseEnter";
        case UDGuiEventHandlerTypeOnMouseExit: return @"onMouseExit";
        case UDGuiEventHandlerTypeOnActivate: return @"onActivate";
        case UDGuiEventHandlerTypeOnDeactivate: return @"onDeactivate";
        case UDGuiEventHandlerTypeOnEsc: return @"onEsc";
        case UDGuiEventHandlerTypeOnEvent: return @"onEvent";
        case UDGuiEventHandlerTypeOnTrigger: return @"onTrigger";
        case UDGuiEventHandlerTypeOnEnter: return @"onEnter";
        case UDGuiEventHandlerTypeOnEnterRelease: return @"onEnterRelease";
    }
}

- (nullable NSString *)eventQualifier {
    return nil;
}

- (void)addCommand:(UDGuiScriptCommand *)command {
    [self insertCommand:command atIndex:_mutableCommands.count];
}

- (void)insertCommand:(UDGuiScriptCommand *)command atIndex:(NSUInteger)index {
    NSParameterAssert(command != nil);
    if (index > _mutableCommands.count) {
        index = _mutableCommands.count;
    }
    [_mutableCommands insertObject:command atIndex:index];
}

- (void)replaceCommandAtIndex:(NSUInteger)index withCommand:(UDGuiScriptCommand *)command {
    NSParameterAssert(command != nil);
    if (index >= _mutableCommands.count) {
        return;
    }
    [_mutableCommands replaceObjectAtIndex:index withObject:command];
}

- (void)removeCommandAtIndex:(NSUInteger)index {
    if (index >= _mutableCommands.count) {
        return;
    }
    [_mutableCommands removeObjectAtIndex:index];
}

- (UDGuiEventHandler *)deepCopy {
    UDGuiEventHandler *copy = [[[self class] alloc] initWithType:self.type];
    for (UDGuiScriptCommand *command in self.commands) {
        [copy addCommand:[command deepCopy]];
    }
    return copy;
}

@end

@implementation UDGuiSimpleEventHandler

- (instancetype)initWithType:(UDGuiEventHandlerType)type {
    return [super initWithType:type];
}

@end

@implementation UDGuiTimedEventHandler

- (instancetype)initWithTimeExpression:(NSString *)timeExpression {
    self = [super initWithType:UDGuiEventHandlerTypeOnTime];
    if (!self) {
        return nil;
    }
    _timeExpression = [((timeExpression ?: @"0")) copy];
    return self;
}

- (nullable NSString *)eventQualifier {
    return self.timeExpression;
}

- (UDGuiEventHandler *)deepCopy {
    UDGuiTimedEventHandler *copy = [[UDGuiTimedEventHandler alloc] initWithTimeExpression:self.timeExpression ?: @"0"];
    for (UDGuiScriptCommand *command in self.commands) {
        [copy addCommand:[command deepCopy]];
    }
    return copy;
}

@end

@implementation UDGuiNamedEventHandler

- (instancetype)initWithEventName:(NSString *)eventName {
    self = [super initWithType:UDGuiEventHandlerTypeOnNamedEvent];
    if (!self) {
        return nil;
    }
    _eventName = [((eventName ?: @"")) copy];
    return self;
}

- (nullable NSString *)eventQualifier {
    return self.eventName;
}

- (UDGuiEventHandler *)deepCopy {
    UDGuiNamedEventHandler *copy = [[UDGuiNamedEventHandler alloc] initWithEventName:self.eventName ?: @""];
    for (UDGuiScriptCommand *command in self.commands) {
        [copy addCommand:[command deepCopy]];
    }
    return copy;
}

@end

@implementation UDGuiWindowNode

@synthesize className = _className;
@synthesize name = _name;
@synthesize parent = _parent;

+ (instancetype)windowNodeWithClassName:(NSString *)className
                                    name:(NSString *)name {
    NSString *lower = className.lowercaseString;
    if ([lower isEqualToString:@"editdef"]) {
        return [[UDEditDefWindowNode alloc] initWithClassName:className name:name];
    }
    if ([lower isEqualToString:@"choicedef"]) {
        return [[UDChoiceDefWindowNode alloc] initWithClassName:className name:name];
    }
    if ([lower isEqualToString:@"sliderdef"]) {
        return [[UDSliderDefWindowNode alloc] initWithClassName:className name:name];
    }
    if ([lower isEqualToString:@"binddef"]) {
        return [[UDBindDefWindowNode alloc] initWithClassName:className name:name];
    }
    if ([lower isEqualToString:@"renderdef"]) {
        return [[UDRenderDefWindowNode alloc] initWithClassName:className name:name];
    }
    if ([lower isEqualToString:@"listdef"]) {
        return [[UDListDefWindowNode alloc] initWithClassName:className name:name];
    }
    return [[UDGuiWindowNode alloc] initWithClassName:className name:name];
}

- (instancetype)initWithClassName:(NSString *)className name:(NSString *)name {
    NSParameterAssert(className.length > 0);
    NSParameterAssert(name.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _className = [className copy];
    _name = [name copy];
    _mutableProperties = [NSMutableArray array];
    _mutableVariableDefinitions = [NSMutableArray array];
    _mutableEventHandlers = [NSMutableArray array];
    _mutableChildren = [NSMutableArray array];
    return self;
}

- (NSArray<UDGuiProperty *> *)properties {
    return [self.mutableProperties copy];
}

- (NSArray<UDGuiVariableDefinition *> *)variableDefinitions {
    return [self.mutableVariableDefinitions copy];
}

- (NSArray<UDGuiEventHandler *> *)eventHandlers {
    return [self.mutableEventHandlers copy];
}

- (NSArray<UDGuiWindowNode *> *)children {
    return [self.mutableChildren copy];
}

- (nullable UDGuiProperty *)propertyForKey:(NSString *)key {
    if (key.length == 0) {
        return nil;
    }
    for (UDGuiProperty *property in self.mutableProperties) {
        if ([property.key caseInsensitiveCompare:key] == NSOrderedSame) {
            return property;
        }
    }
    return nil;
}

- (void)setPropertyValue:(NSString *)value forKey:(NSString *)key {
    NSParameterAssert(key.length > 0);
    NSParameterAssert(value != nil);

    for (NSUInteger idx = 0; idx < self.mutableProperties.count; idx++) {
        UDGuiProperty *existing = [self.mutableProperties objectAtIndex:idx];
        if ([existing.key caseInsensitiveCompare:key] == NSOrderedSame) {
            [self.mutableProperties replaceObjectAtIndex:idx withObject:[[UDGuiProperty alloc] initWithKey:existing.key value:value]];
            return;
        }
    }

    [self.mutableProperties addObject:[[UDGuiProperty alloc] initWithKey:key value:value]];
}

- (void)removePropertyForKey:(NSString *)key {
    if (key.length == 0) {
        return;
    }

    for (NSUInteger idx = 0; idx < self.mutableProperties.count; idx++) {
        UDGuiProperty *existing = [self.mutableProperties objectAtIndex:idx];
        if ([existing.key caseInsensitiveCompare:key] == NSOrderedSame) {
            [self.mutableProperties removeObjectAtIndex:idx];
            return;
        }
    }
}

- (nullable NSString *)stringPropertyForKey:(NSString *)key {
    return [self propertyForKey:key].value;
}

- (nullable NSNumber *)numberPropertyForKey:(NSString *)key {
    NSString *value = [self stringPropertyForKey:key];
    if (value.length == 0) {
        return nil;
    }

    NSScanner *scanner = [NSScanner scannerWithString:value];
    double parsed = 0.0;
    if (![scanner scanDouble:&parsed] || !scanner.isAtEnd) {
        return nil;
    }
    return @(parsed);
}

- (BOOL)boolPropertyForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    NSString *value = [[self stringPropertyForKey:key] lowercaseString];
    if (value.length == 0) {
        return defaultValue;
    }
    return [value isEqualToString:@"1"] || [value isEqualToString:@"true"] || [value isEqualToString:@"yes"];
}

- (void)setNumberPropertyValue:(double)value forKey:(NSString *)key {
    [self setPropertyValue:[NSString stringWithFormat:@"%g", value] forKey:key];
}

- (void)setBoolPropertyValue:(BOOL)value forKey:(NSString *)key {
    [self setPropertyValue:(value ? @"1" : @"0") forKey:key];
}

- (NSString *)defaultedStringPropertyForKey:(NSString *)key defaultValue:(NSString *)defaultValue {
    NSString *value = [self stringPropertyForKey:key];
    return value.length > 0 ? value : defaultValue;
}

- (void)setOptionalStringPropertyValue:(NSString *)value forKey:(NSString *)key {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        [self removePropertyForKey:key];
        return;
    }
    [self setPropertyValue:trimmed forKey:key];
}

- (BOOL)showTime {
    return [self boolPropertyForKey:@"showtime" defaultValue:NO];
}

- (void)setShowTime:(BOOL)showTime {
    [self setBoolPropertyValue:showTime forKey:@"showtime"];
}

- (BOOL)showCoords {
    return [self boolPropertyForKey:@"showcoords" defaultValue:NO];
}

- (void)setShowCoords:(BOOL)showCoords {
    [self setBoolPropertyValue:showCoords forKey:@"showcoords"];
}

- (BOOL)visible {
    return [self boolPropertyForKey:@"visible" defaultValue:YES];
}

- (void)setVisible:(BOOL)visible {
    [self setBoolPropertyValue:visible forKey:@"visible"];
}

- (BOOL)noEvents {
    return [self boolPropertyForKey:@"noevents" defaultValue:NO];
}

- (void)setNoEvents:(BOOL)noEvents {
    [self setBoolPropertyValue:noEvents forKey:@"noevents"];
}

- (double)forceAspectWidth {
    NSNumber *value = [self numberPropertyForKey:@"forceaspectwidth"];
    return value ? value.doubleValue : 640.0;
}

- (void)setForceAspectWidth:(double)forceAspectWidth {
    [self setNumberPropertyValue:forceAspectWidth forKey:@"forceaspectwidth"];
}

- (double)forceAspectHeight {
    NSNumber *value = [self numberPropertyForKey:@"forceaspectheight"];
    return value ? value.doubleValue : 480.0;
}

- (void)setForceAspectHeight:(double)forceAspectHeight {
    [self setNumberPropertyValue:forceAspectHeight forKey:@"forceaspectheight"];
}

- (double)matScaleX {
    NSNumber *value = [self numberPropertyForKey:@"matscalex"];
    return value ? value.doubleValue : 1.0;
}

- (void)setMatScaleX:(double)matScaleX {
    [self setNumberPropertyValue:matScaleX forKey:@"matscalex"];
}

- (double)matScaleY {
    NSNumber *value = [self numberPropertyForKey:@"matscaley"];
    return value ? value.doubleValue : 1.0;
}

- (void)setMatScaleY:(double)matScaleY {
    [self setNumberPropertyValue:matScaleY forKey:@"matscaley"];
}

- (double)borderSize {
    NSNumber *value = [self numberPropertyForKey:@"bordersize"];
    return value ? value.doubleValue : 0.0;
}

- (void)setBorderSize:(double)borderSize {
    [self setNumberPropertyValue:borderSize forKey:@"bordersize"];
}

- (NSString *)foreColor {
    return [self defaultedStringPropertyForKey:@"forecolor" defaultValue:@"1, 1, 1, 1"];
}

- (void)setForeColor:(NSString *)foreColor {
    [self setOptionalStringPropertyValue:foreColor forKey:@"forecolor"];
}

- (NSString *)hoverColor {
    return [self defaultedStringPropertyForKey:@"hovercolor" defaultValue:@"1, 1, 1, 1"];
}

- (void)setHoverColor:(NSString *)hoverColor {
    [self setOptionalStringPropertyValue:hoverColor forKey:@"hovercolor"];
}

- (NSString *)backColor {
    return [self defaultedStringPropertyForKey:@"backcolor" defaultValue:@"0, 0, 0, 0"];
}

- (void)setBackColor:(NSString *)backColor {
    [self setOptionalStringPropertyValue:backColor forKey:@"backcolor"];
}

- (NSString *)borderColor {
    return [self defaultedStringPropertyForKey:@"bordercolor" defaultValue:@"0, 0, 0, 0"];
}

- (void)setBorderColor:(NSString *)borderColor {
    [self setOptionalStringPropertyValue:borderColor forKey:@"bordercolor"];
}

- (NSString *)matColor {
    return [self defaultedStringPropertyForKey:@"matcolor" defaultValue:@"1, 1, 1, 1"];
}

- (void)setMatColor:(NSString *)matColor {
    [self setOptionalStringPropertyValue:matColor forKey:@"matcolor"];
}

- (nullable NSString *)scale {
    return [self stringPropertyForKey:@"scale"];
}

- (void)setScale:(NSString *)scale {
    [self setOptionalStringPropertyValue:scale forKey:@"scale"];
}

- (nullable NSString *)translate {
    return [self stringPropertyForKey:@"translate"];
}

- (void)setTranslate:(NSString *)translate {
    [self setOptionalStringPropertyValue:translate forKey:@"translate"];
}

- (BOOL)noWrap {
    return [self boolPropertyForKey:@"nowrap" defaultValue:NO];
}

- (void)setNoWrap:(BOOL)noWrap {
    [self setBoolPropertyValue:noWrap forKey:@"nowrap"];
}

- (BOOL)shadow {
    return [self boolPropertyForKey:@"shadow" defaultValue:NO];
}

- (void)setShadow:(BOOL)shadow {
    [self setBoolPropertyValue:shadow forKey:@"shadow"];
}

- (double)textScale {
    NSNumber *value = [self numberPropertyForKey:@"textscale"];
    return value ? value.doubleValue : 1.0;
}

- (void)setTextScale:(double)textScale {
    [self setNumberPropertyValue:textScale forKey:@"textscale"];
}

- (NSInteger)textAlign {
    NSNumber *value = [self numberPropertyForKey:@"textalign"];
    return value ? value.integerValue : 0;
}

- (void)setTextAlign:(NSInteger)textAlign {
    [self setNumberPropertyValue:(double)textAlign forKey:@"textalign"];
}

- (double)textAlignX {
    NSNumber *value = [self numberPropertyForKey:@"textalignx"];
    return value ? value.doubleValue : 0.0;
}

- (void)setTextAlignX:(double)textAlignX {
    [self setNumberPropertyValue:textAlignX forKey:@"textalignx"];
}

- (double)textAlignY {
    NSNumber *value = [self numberPropertyForKey:@"textaligny"];
    return value ? value.doubleValue : 0.0;
}

- (void)setTextAlignY:(double)textAlignY {
    [self setNumberPropertyValue:textAlignY forKey:@"textaligny"];
}

- (NSString *)shear {
    NSString *value = [self stringPropertyForKey:@"shear"];
    return value.length > 0 ? value : @"0, 0";
}

- (void)setShear:(NSString *)shear {
    [self setPropertyValue:((shear ?: @"").length > 0 ? shear : @"0, 0") forKey:@"shear"];
}

- (BOOL)wantEnter {
    return [self boolPropertyForKey:@"wantenter" defaultValue:NO];
}

- (void)setWantEnter:(BOOL)wantEnter {
    [self setBoolPropertyValue:wantEnter forKey:@"wantenter"];
}

- (BOOL)naturalMatScale {
    return [self boolPropertyForKey:@"naturalmatscale" defaultValue:NO];
}

- (void)setNaturalMatScale:(BOOL)naturalMatScale {
    [self setBoolPropertyValue:naturalMatScale forKey:@"naturalmatscale"];
}

- (BOOL)noClip {
    return [self boolPropertyForKey:@"noclip" defaultValue:NO];
}

- (void)setNoClip:(BOOL)noClip {
    [self setBoolPropertyValue:noClip forKey:@"noclip"];
}

- (BOOL)noCursor {
    return [self boolPropertyForKey:@"nocursor" defaultValue:NO];
}

- (void)setNoCursor:(BOOL)noCursor {
    [self setBoolPropertyValue:noCursor forKey:@"nocursor"];
}

- (BOOL)menuGUI {
    return [self boolPropertyForKey:@"menugui" defaultValue:NO];
}

- (void)setMenuGUI:(BOOL)menuGUI {
    [self setBoolPropertyValue:menuGUI forKey:@"menugui"];
}

- (BOOL)modal {
    return [self boolPropertyForKey:@"modal" defaultValue:NO];
}

- (void)setModal:(BOOL)modal {
    [self setBoolPropertyValue:modal forKey:@"modal"];
}

- (BOOL)invertRect {
    return [self boolPropertyForKey:@"invertrect" defaultValue:NO];
}

- (void)setInvertRect:(BOOL)invertRect {
    [self setBoolPropertyValue:invertRect forKey:@"invertrect"];
}

- (NSString *)nameOverride {
    NSString *value = [self stringPropertyForKey:@"name"];
    return value.length > 0 ? value : self.name;
}

- (void)setNameOverride:(NSString *)nameOverride {
    NSString *value = [nameOverride stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0 || [value isEqualToString:self.name]) {
        [self removePropertyForKey:@"name"];
        return;
    }
    [self setPropertyValue:value forKey:@"name"];
}

- (nullable NSString *)text {
    return [self stringPropertyForKey:@"text"];
}

- (void)setText:(NSString *)text {
    [self setOptionalStringPropertyValue:text forKey:@"text"];
}

- (nullable NSString *)background {
    return [self stringPropertyForKey:@"background"];
}

- (void)setBackground:(NSString *)background {
    [self setOptionalStringPropertyValue:background forKey:@"background"];
}

- (nullable NSString *)varBackground {
    return [self stringPropertyForKey:@"varbackground"];
}

- (void)setVarBackground:(NSString *)varBackground {
    [self setOptionalStringPropertyValue:varBackground forKey:@"varbackground"];
}

- (nullable NSString *)runScript {
    return [self stringPropertyForKey:@"runscript"];
}

- (void)setRunScript:(NSString *)runScript {
    [self setOptionalStringPropertyValue:runScript forKey:@"runscript"];
}

- (nullable NSString *)play {
    return [self stringPropertyForKey:@"play"];
}

- (void)setPlay:(NSString *)play {
    NSString *value = [play stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0) {
        [self removePropertyForKey:@"play"];
        return;
    }
    [self setPropertyValue:value forKey:@"play"];
}

- (nullable NSString *)comment {
    return [self stringPropertyForKey:@"comment"];
}

- (void)setComment:(NSString *)comment {
    NSString *value = [comment stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0) {
        [self removePropertyForKey:@"comment"];
        return;
    }
    [self setPropertyValue:value forKey:@"comment"];
}

- (nullable NSString *)font {
    return [self stringPropertyForKey:@"font"];
}

- (void)setFont:(NSString *)font {
    NSString *value = [font stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0) {
        [self removePropertyForKey:@"font"];
        return;
    }
    [self setPropertyValue:value forKey:@"font"];
}

- (void)addVariableDefinition:(UDGuiVariableDefinition *)definition {
    [self insertVariableDefinition:definition atIndex:self.mutableVariableDefinitions.count];
}

- (void)insertVariableDefinition:(UDGuiVariableDefinition *)definition atIndex:(NSUInteger)index {
    NSParameterAssert(definition != nil);

    if (index > self.mutableVariableDefinitions.count) {
        index = self.mutableVariableDefinitions.count;
    }

    [self.mutableVariableDefinitions insertObject:definition atIndex:index];
}

- (void)replaceVariableDefinitionAtIndex:(NSUInteger)index withDefinition:(UDGuiVariableDefinition *)definition {
    NSParameterAssert(definition != nil);

    if (index >= self.mutableVariableDefinitions.count) {
        return;
    }

    [self.mutableVariableDefinitions replaceObjectAtIndex:index withObject:definition];
}

- (void)removeVariableDefinitionAtIndex:(NSUInteger)index {
    if (index >= self.mutableVariableDefinitions.count) {
        return;
    }

    [self.mutableVariableDefinitions removeObjectAtIndex:index];
}

- (void)addEventHandler:(UDGuiEventHandler *)eventHandler {
    [self insertEventHandler:eventHandler atIndex:self.mutableEventHandlers.count];
}

- (void)insertEventHandler:(UDGuiEventHandler *)eventHandler atIndex:(NSUInteger)index {
    NSParameterAssert(eventHandler != nil);
    if (index > self.mutableEventHandlers.count) {
        index = self.mutableEventHandlers.count;
    }
    [self.mutableEventHandlers insertObject:eventHandler atIndex:index];
}

- (void)replaceEventHandlerAtIndex:(NSUInteger)index withEventHandler:(UDGuiEventHandler *)eventHandler {
    NSParameterAssert(eventHandler != nil);
    if (index >= self.mutableEventHandlers.count) {
        return;
    }
    [self.mutableEventHandlers replaceObjectAtIndex:index withObject:eventHandler];
}

- (void)removeEventHandlerAtIndex:(NSUInteger)index {
    if (index >= self.mutableEventHandlers.count) {
        return;
    }
    [self.mutableEventHandlers removeObjectAtIndex:index];
}

- (id)valueForUndefinedKey:(NSString *)key {
    return [self stringPropertyForKey:key];
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    if (value == nil) {
        [self removePropertyForKey:key];
        return;
    }

    if ([value isKindOfClass:[NSString class]]) {
        [self setPropertyValue:(NSString *)value forKey:key];
        return;
    }

    if ([value isKindOfClass:[NSNumber class]]) {
        [self setPropertyValue:[(NSNumber *)value stringValue] forKey:key];
        return;
    }

    [self setPropertyValue:[value description] forKey:key];
}

- (void)addChild:(UDGuiWindowNode *)child {
    [self insertChild:child atIndex:self.mutableChildren.count];
}

- (void)insertChild:(UDGuiWindowNode *)child atIndex:(NSUInteger)index {
    NSParameterAssert(child != nil);

    if (index > self.mutableChildren.count) {
        index = self.mutableChildren.count;
    }

    child.parent = self;
    [self.mutableChildren insertObject:child atIndex:index];
}

- (void)removeChild:(UDGuiWindowNode *)child {
    NSUInteger idx = [self.mutableChildren indexOfObjectIdenticalTo:child];
    if (idx == NSNotFound) {
        return;
    }

    child.parent = nil;
    [self.mutableChildren removeObjectAtIndex:idx];
}

- (NSUInteger)indexOfChild:(UDGuiWindowNode *)child {
    NSUInteger idx = [self.mutableChildren indexOfObjectIdenticalTo:child];
    return idx == NSNotFound ? NSNotFound : idx;
}

- (UDGuiWindowNode *)deepCopy {
    UDGuiWindowNode *copy = [[[self class] alloc] initWithClassName:self.className name:self.name];

    for (UDGuiProperty *property in self.mutableProperties) {
        [copy.mutableProperties addObject:[[UDGuiProperty alloc] initWithKey:property.key value:property.value]];
    }

    for (UDGuiVariableDefinition *definition in self.mutableVariableDefinitions) {
        [copy.mutableVariableDefinitions addObject:[[UDGuiVariableDefinition alloc] initWithType:definition.type
                                                                                             name:definition.name
                                                                                            value:definition.value]];
    }

    for (UDGuiEventHandler *eventHandler in self.mutableEventHandlers) {
        [copy.mutableEventHandlers addObject:[eventHandler deepCopy]];
    }

    for (UDGuiWindowNode *child in self.mutableChildren) {
        [copy addChild:[child deepCopy]];
    }

    return copy;
}

- (BOOL)validateRect:(id  _Nullable __autoreleasing *)ioValue error:(NSError * _Nullable __autoreleasing *)outError {
    NSString *value = [*ioValue isKindOfClass:[NSString class]] ? *ioValue : @"";
    if (value.length == 0 || UDGuiIsRectString(value)) {
        return YES;
    }
    if (outError) {
        *outError = [NSError errorWithDomain:UDGuiValidationErrorDomain
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Expected 4 numeric values: x, y, w, h"}];
    }
    return NO;
}

- (BOOL)validateRotate:(id  _Nullable __autoreleasing *)ioValue error:(NSError * _Nullable __autoreleasing *)outError {
    NSString *value = [*ioValue isKindOfClass:[NSString class]] ? *ioValue : @"";
    if (value.length == 0 || UDGuiIsScalarString(value)) {
        return YES;
    }
    if (outError) {
        *outError = [NSError errorWithDomain:UDGuiValidationErrorDomain
                                        code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"Expected numeric rotate value"}];
    }
    return NO;
}

@end

@implementation UDEditDefWindowNode

- (nullable NSString *)cvar {
    return [self stringPropertyForKey:@"cvar"];
}

- (void)setCvar:(NSString *)cvar {
    [self setPropertyValue:(cvar ?: @"") forKey:@"cvar"];
}

- (NSInteger)maxChars {
    NSNumber *value = [self numberPropertyForKey:@"maxchars"];
    return value ? value.integerValue : 128;
}

- (void)setMaxChars:(NSInteger)maxChars {
    [self setNumberPropertyValue:(double)maxChars forKey:@"maxchars"];
}

- (BOOL)numeric {
    return [self boolPropertyForKey:@"numeric" defaultValue:NO];
}

- (void)setNumeric:(BOOL)numeric {
    [self setBoolPropertyValue:numeric forKey:@"numeric"];
}

- (BOOL)wrap {
    return [self boolPropertyForKey:@"wrap" defaultValue:NO];
}

- (void)setWrap:(BOOL)wrap {
    [self setBoolPropertyValue:wrap forKey:@"wrap"];
}

- (BOOL)readOnly {
    return [self boolPropertyForKey:@"readonly" defaultValue:NO];
}

- (void)setReadOnly:(BOOL)readOnly {
    [self setBoolPropertyValue:readOnly forKey:@"readonly"];
}

- (BOOL)forceScroll {
    return [self boolPropertyForKey:@"forcescroll" defaultValue:NO];
}

- (void)setForceScroll:(BOOL)forceScroll {
    [self setBoolPropertyValue:forceScroll forKey:@"forcescroll"];
}

- (nullable NSString *)source {
    return [self stringPropertyForKey:@"source"];
}

- (void)setSource:(NSString *)source {
    [self setPropertyValue:(source ?: @"") forKey:@"source"];
}

- (BOOL)password {
    return [self boolPropertyForKey:@"password" defaultValue:NO];
}

- (void)setPassword:(BOOL)password {
    [self setBoolPropertyValue:password forKey:@"password"];
}

- (BOOL)liveUpdate {
    return [self boolPropertyForKey:@"liveupdate" defaultValue:YES];
}

- (void)setLiveUpdate:(BOOL)liveUpdate {
    [self setBoolPropertyValue:liveUpdate forKey:@"liveupdate"];
}

- (nullable NSString *)cvarGroup {
    return [self stringPropertyForKey:@"cvargroup"];
}

- (void)setCvarGroup:(NSString *)cvarGroup {
    [self setPropertyValue:(cvarGroup ?: @"") forKey:@"cvargroup"];
}

@end

@implementation UDChoiceDefWindowNode

- (NSInteger)choiceType {
    return [self numberPropertyForKey:@"choicetype"].integerValue;
}

- (void)setChoiceType:(NSInteger)choiceType {
    [self setNumberPropertyValue:(double)choiceType forKey:@"choicetype"];
}

- (nullable NSString *)gui {
    return [self stringPropertyForKey:@"gui"];
}

- (void)setGui:(NSString *)gui {
    [self setPropertyValue:(gui ?: @"") forKey:@"gui"];
}

- (nullable NSString *)cvar {
    return [self stringPropertyForKey:@"cvar"];
}

- (void)setCvar:(NSString *)cvar {
    [self setPropertyValue:(cvar ?: @"") forKey:@"cvar"];
}

- (nullable NSString *)choices {
    return [self stringPropertyForKey:@"choices"];
}

- (void)setChoices:(NSString *)choices {
    [self setPropertyValue:(choices ?: @"") forKey:@"choices"];
}

- (nullable NSString *)values {
    NSString *values = [self stringPropertyForKey:@"values"];
    return values.length > 0 ? values : self.choices;
}

- (void)setValues:(NSString *)values {
    [self setPropertyValue:(values ?: @"") forKey:@"values"];
}

- (NSInteger)currentChoice {
    return [self numberPropertyForKey:@"currentchoice"].integerValue;
}

- (void)setCurrentChoice:(NSInteger)currentChoice {
    [self setNumberPropertyValue:(double)currentChoice forKey:@"currentchoice"];
}

- (BOOL)liveUpdate {
    return [self boolPropertyForKey:@"liveupdate" defaultValue:YES];
}

- (void)setLiveUpdate:(BOOL)liveUpdate {
    [self setBoolPropertyValue:liveUpdate forKey:@"liveupdate"];
}

- (nullable NSString *)cvarGroup {
    return [self stringPropertyForKey:@"cvargroup"];
}

- (void)setCvarGroup:(NSString *)cvarGroup {
    [self setPropertyValue:(cvarGroup ?: @"") forKey:@"cvargroup"];
}

@end

@implementation UDSliderDefWindowNode

- (nullable NSString *)cvar {
    return [self stringPropertyForKey:@"cvar"];
}

- (void)setCvar:(NSString *)cvar {
    [self setPropertyValue:(cvar ?: @"") forKey:@"cvar"];
}

- (double)low {
    NSNumber *value = [self numberPropertyForKey:@"low"];
    return value ? value.doubleValue : 0.0;
}

- (void)setLow:(double)low {
    [self setNumberPropertyValue:low forKey:@"low"];
}

- (double)high {
    NSNumber *value = [self numberPropertyForKey:@"high"];
    return value ? value.doubleValue : 100.0;
}

- (void)setHigh:(double)high {
    [self setNumberPropertyValue:high forKey:@"high"];
}

- (double)stepSize {
    NSNumber *value = [self numberPropertyForKey:@"stepsize"];
    if (!value) {
        value = [self numberPropertyForKey:@"step"];
    }
    return value ? value.doubleValue : 1.0;
}

- (void)setStepSize:(double)stepSize {
    [self setNumberPropertyValue:stepSize forKey:@"stepsize"];
    [self removePropertyForKey:@"step"];
}

- (BOOL)vertical {
    return [self boolPropertyForKey:@"vertical" defaultValue:NO];
}

- (void)setVertical:(BOOL)vertical {
    [self setBoolPropertyValue:vertical forKey:@"vertical"];
}

- (BOOL)scrollBar {
    return [self boolPropertyForKey:@"scrollbar" defaultValue:NO];
}

- (void)setScrollBar:(BOOL)scrollBar {
    [self setBoolPropertyValue:scrollBar forKey:@"scrollbar"];
}

- (nullable NSString *)thumbShader {
    return [self stringPropertyForKey:@"thumbshader"];
}

- (void)setThumbShader:(NSString *)thumbShader {
    [self setPropertyValue:(thumbShader ?: @"") forKey:@"thumbshader"];
}

- (BOOL)liveUpdate {
    return [self boolPropertyForKey:@"liveupdate" defaultValue:YES];
}

- (void)setLiveUpdate:(BOOL)liveUpdate {
    [self setBoolPropertyValue:liveUpdate forKey:@"liveupdate"];
}

- (nullable NSString *)cvarGroup {
    return [self stringPropertyForKey:@"cvargroup"];
}

- (void)setCvarGroup:(NSString *)cvarGroup {
    [self setPropertyValue:(cvarGroup ?: @"") forKey:@"cvargroup"];
}

@end

@implementation UDBindDefWindowNode

- (nullable NSString *)bind {
    return [self stringPropertyForKey:@"bind"];
}

- (void)setBind:(NSString *)bind {
    [self setPropertyValue:(bind ?: @"") forKey:@"bind"];
}

@end

@implementation UDRenderDefWindowNode

- (nullable NSString *)model {
    return [self stringPropertyForKey:@"model"];
}

- (void)setModel:(NSString *)model {
    [self setPropertyValue:(model ?: @"") forKey:@"model"];
}

- (nullable NSString *)anim {
    return [self stringPropertyForKey:@"anim"];
}

- (void)setAnim:(NSString *)anim {
    [self setPropertyValue:(anim ?: @"") forKey:@"anim"];
}

- (nullable NSString *)animClass {
    return [self stringPropertyForKey:@"animclass"];
}

- (void)setAnimClass:(NSString *)animClass {
    [self setPropertyValue:(animClass ?: @"") forKey:@"animclass"];
}

- (nullable NSString *)lightOrigin {
    NSString *value = [self stringPropertyForKey:@"lightorigin"];
    return value.length > 0 ? value : @"-128,0,0,1";
}

- (void)setLightOrigin:(NSString *)lightOrigin {
    [self setPropertyValue:(lightOrigin ?: @"") forKey:@"lightorigin"];
}

- (nullable NSString *)lightColor {
    NSString *value = [self stringPropertyForKey:@"lightcolor"];
    return value.length > 0 ? value : @"1,1,1,1";
}

- (void)setLightColor:(NSString *)lightColor {
    [self setPropertyValue:(lightColor ?: @"") forKey:@"lightcolor"];
}

- (nullable NSString *)modelOrigin {
    NSString *value = [self stringPropertyForKey:@"modelorigin"];
    return value.length > 0 ? value : @"0,0,0,0";
}

- (void)setModelOrigin:(NSString *)modelOrigin {
    [self setPropertyValue:(modelOrigin ?: @"") forKey:@"modelorigin"];
}

- (nullable NSString *)modelRotate {
    NSString *value = [self stringPropertyForKey:@"modelrotate"];
    return value.length > 0 ? value : @"0,0,0,0";
}

- (void)setModelRotate:(NSString *)modelRotate {
    [self setPropertyValue:(modelRotate ?: @"") forKey:@"modelrotate"];
}

- (nullable NSString *)viewOffset {
    NSString *value = [self stringPropertyForKey:@"viewoffset"];
    return value.length > 0 ? value : @"-128,0,0,1";
}

- (void)setViewOffset:(NSString *)viewOffset {
    [self setPropertyValue:(viewOffset ?: @"") forKey:@"viewoffset"];
}

- (BOOL)needsRender {
    return [self boolPropertyForKey:@"needsrender" defaultValue:YES];
}

- (void)setNeedsRender:(BOOL)needsRender {
    [self setBoolPropertyValue:needsRender forKey:@"needsrender"];
}

@end

@implementation UDListDefWindowNode

- (BOOL)horizontal {
    return [self boolPropertyForKey:@"horizontal" defaultValue:NO];
}

- (void)setHorizontal:(BOOL)horizontal {
    [self setBoolPropertyValue:horizontal forKey:@"horizontal"];
}

- (nullable NSString *)listName {
    return [self stringPropertyForKey:@"listname"];
}

- (void)setListName:(NSString *)listName {
    [self setPropertyValue:(listName ?: @"") forKey:@"listname"];
}

- (nullable NSString *)tabStops {
    return [self stringPropertyForKey:@"tabstops"];
}

- (void)setTabStops:(NSString *)tabStops {
    [self setPropertyValue:(tabStops ?: @"") forKey:@"tabstops"];
}

- (nullable NSString *)tabAligns {
    return [self stringPropertyForKey:@"tabaligns"];
}

- (void)setTabAligns:(NSString *)tabAligns {
    [self setPropertyValue:(tabAligns ?: @"") forKey:@"tabaligns"];
}

- (BOOL)multipleSelection {
    return [self boolPropertyForKey:@"multiplesel" defaultValue:NO];
}

- (void)setMultipleSelection:(BOOL)multipleSelection {
    [self setBoolPropertyValue:multipleSelection forKey:@"multiplesel"];
}

- (BOOL)validateTabStops:(id  _Nullable __autoreleasing *)ioValue error:(NSError * _Nullable __autoreleasing *)outError {
    NSString *value = [*ioValue isKindOfClass:[NSString class]] ? *ioValue : @"";
    if (value.length == 0 || UDGuiIsCommaSeparatedIntegerList(value)) {
        return YES;
    }
    if (outError) {
        *outError = [NSError errorWithDomain:UDGuiValidationErrorDomain
                                        code:3
                                    userInfo:@{NSLocalizedDescriptionKey: @"tabstops must be comma-separated integers"}];
    }
    return NO;
}

- (BOOL)validateTabAligns:(id  _Nullable __autoreleasing *)ioValue error:(NSError * _Nullable __autoreleasing *)outError {
    NSString *value = [*ioValue isKindOfClass:[NSString class]] ? *ioValue : @"";
    if (value.length == 0 || UDGuiIsCommaSeparatedAlignmentList(value)) {
        return YES;
    }
    if (outError) {
        *outError = [NSError errorWithDomain:UDGuiValidationErrorDomain
                                        code:4
                                    userInfo:@{NSLocalizedDescriptionKey: @"tabaligns must be 0,1,2 values"}];
    }
    return NO;
}

@end

@implementation UDGuiDocument

@synthesize sourceVirtualPath = _sourceVirtualPath;

- (instancetype)initWithSourceVirtualPath:(NSString *)sourceVirtualPath {
    NSParameterAssert(sourceVirtualPath.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _sourceVirtualPath = [sourceVirtualPath copy];
    _mutableRootWindows = [NSMutableArray array];
    return self;
}

- (NSArray<UDGuiWindowNode *> *)rootWindows {
    return [self.mutableRootWindows copy];
}

- (void)addRootWindow:(UDGuiWindowNode *)window {
    [self insertRootWindow:window atIndex:self.mutableRootWindows.count];
}

- (void)insertRootWindow:(UDGuiWindowNode *)window atIndex:(NSUInteger)index {
    NSParameterAssert(window != nil);

    if (index > self.mutableRootWindows.count) {
        index = self.mutableRootWindows.count;
    }

    window.parent = nil;
    [self.mutableRootWindows insertObject:window atIndex:index];
}

- (void)removeRootWindow:(UDGuiWindowNode *)window {
    NSUInteger idx = [self.mutableRootWindows indexOfObjectIdenticalTo:window];
    if (idx == NSNotFound) {
        return;
    }

    [self.mutableRootWindows removeObjectAtIndex:idx];
}

- (NSUInteger)indexOfRootWindow:(UDGuiWindowNode *)window {
    NSUInteger idx = [self.mutableRootWindows indexOfObjectIdenticalTo:window];
    return idx == NSNotFound ? NSNotFound : idx;
}

@end


@implementation UDGuiExpression
- (id)copyWithZone:(nullable NSZone *)zone {
    return [self deepCopy];
}
- (NSString *)serializedString {
    return @"";
}
- (UDGuiExpression *)deepCopy {
    return [[[self class] alloc] init];
}
@end

@implementation UDGuiLiteralExpression
@synthesize value = _value;
@synthesize isQuoted = _isQuoted;

- (instancetype)initWithValue:(NSString *)value isQuoted:(BOOL)isQuoted {
    self = [super init];
    if (self) {
        _value = [value copy];
        _isQuoted = isQuoted;
    }
    return self;
}

- (NSString *)serializedString {
    if (self.isQuoted) {
        return [NSString stringWithFormat:@"\"%@\"", self.value];
    }
    return self.value;
}

- (UDGuiExpression *)deepCopy {
    return [[UDGuiLiteralExpression alloc] initWithValue:self.value isQuoted:self.isQuoted];
}
@end

@implementation UDGuiVariableExpression
@synthesize name = _name;

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _name = [name copy];
    }
    return self;
}

- (NSString *)serializedString {
    return self.name;
}

- (UDGuiExpression *)deepCopy {
    return [[UDGuiVariableExpression alloc] initWithName:self.name];
}
@end

@implementation UDGuiParenthesizedExpression
@synthesize expression = _expression;

- (instancetype)initWithExpression:(UDGuiExpression *)expression {
    self = [super init];
    if (self) {
        _expression = expression;
    }
    return self;
}

- (NSString *)serializedString {
    return [NSString stringWithFormat:@"( %@ )", [self.expression serializedString]];
}

- (UDGuiExpression *)deepCopy {
    return [[UDGuiParenthesizedExpression alloc] initWithExpression:[self.expression deepCopy]];
}
@end

@implementation UDGuiUnaryExpression
@synthesize operatorString = _operatorString;
@synthesize operand = _operand;

- (instancetype)initWithOperator:(NSString *)operatorString operand:(UDGuiExpression *)operand {
    self = [super init];
    if (self) {
        _operatorString = [operatorString copy];
        _operand = operand;
    }
    return self;
}

- (NSString *)serializedString {
    return [NSString stringWithFormat:@"%@%@", self.operatorString, [self.operand serializedString]];
}

- (UDGuiExpression *)deepCopy {
    return [[UDGuiUnaryExpression alloc] initWithOperator:self.operatorString operand:[self.operand deepCopy]];
}
@end

@implementation UDGuiBinaryExpression
@synthesize left = _left;
@synthesize operatorString = _operatorString;
@synthesize right = _right;

- (instancetype)initWithLeft:(UDGuiExpression *)left operator:(NSString *)operatorString right:(UDGuiExpression *)right {
    self = [super init];
    if (self) {
        _left = left;
        _operatorString = [operatorString copy];
        _right = right;
    }
    return self;
}

- (NSString *)serializedString {
    return [NSString stringWithFormat:@"%@ %@ %@", [self.left serializedString], self.operatorString, [self.right serializedString]];
}

- (UDGuiExpression *)deepCopy {
    return [[UDGuiBinaryExpression alloc] initWithLeft:[self.left deepCopy] operator:self.operatorString right:[self.right deepCopy]];
}
@end

@implementation UDGuiIfBranch

@synthesize condition = _condition;
@synthesize commands = _commands;

- (instancetype)initWithCondition:(nullable UDGuiExpression *)condition commands:(NSArray<UDGuiScriptCommand *> *)commands {
    self = [super init];
    if (self) {
        _condition = condition;
        _commands = [commands copy];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return [self deepCopy];
}

- (UDGuiIfBranch *)deepCopy {
    NSMutableArray *copiedCommands = [NSMutableArray array];
    for (UDGuiScriptCommand *cmd in self.commands) {
        [copiedCommands addObject:[cmd deepCopy]];
    }
    return [[UDGuiIfBranch alloc] initWithCondition:[self.condition deepCopy] commands:copiedCommands];
}

@end

@implementation UDGuiIfCommand

@synthesize branches = _branches;

- (instancetype)initWithBranches:(NSArray<UDGuiIfBranch *> *)branches {
    self = [super initWithKeyword:@"if" arguments:@""];
    if (self) {
        _branches = [branches copy];
    }
    return self;
}

- (NSString *)serializedStatement {
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger idx = 0; idx < self.branches.count; idx++) {
        UDGuiIfBranch *branch = [self.branches objectAtIndex:idx];
        if (idx > 0) {
            [result appendString:@" "];
        }
        if (branch.condition) {
            if (idx == 0) {
                [result appendFormat:@"if ( %@ ) {", [branch.condition serializedString]];
            } else {
                [result appendFormat:@"else if ( %@ ) {", [branch.condition serializedString]];
            }
        } else {
            [result appendString:@"else {"];
        }
        
        for (UDGuiScriptCommand *cmd in branch.commands) {
            [result appendFormat:@" %@ ;", [cmd serializedStatement]];
        }
        
        [result appendString:@" }"];
    }
    return result;
}

- (UDGuiScriptCommand *)deepCopy {
    NSMutableArray *copiedBranches = [NSMutableArray array];
    for (UDGuiIfBranch *branch in self.branches) {
        [copiedBranches addObject:[branch deepCopy]];
    }
    return [[UDGuiIfCommand alloc] initWithBranches:copiedBranches];
}

@end
