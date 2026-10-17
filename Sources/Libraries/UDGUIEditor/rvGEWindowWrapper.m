/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEWindowWrapper.m — tools/guied/GEWindowWrapper.cpp, ported, and
 * IsExpression from tools/guied/guied.cpp.
 */

#import "rvGEWindowWrapper.h"
#import "idWindow.h"
#import "idWinVar.h"
#import "idDict.h"
#import "idParser.h"
#import "idToken.h"
#import "idStr.h"
#import "idEditWindow.h"
#import "idListWindow.h"
#import "idBindWindow.h"
#import "idRenderWindow.h"
#import "idChoiceWindow.h"
#import "idSliderWindow.h"

/// idStr::StripTrailingWhitespace
static NSString *UDStripTrailing(NSString *s, NSCharacterSet *white) {
    NSUInteger end = s.length;
    while ( end > 0 && [white characterIsMember:[s characterAtIndex:end - 1]] ) {
        end--;
    }
    return [s substringToIndex:end];
}

@implementation rvGEWindowWrapper {
    idRectangle mClientRect;
    idRectangle mScreenRect;
    BOOL mOldVisible;
    BOOL mMoveable;
}

- (instancetype)initWithWindow:(idWindow *)window type:(rvGEWindowType)type {
    self = [super init];
    if (self) {
        NSParameterAssert(window);

        _window = window;
        _flippedHorz = NO;
        _flippedVert = NO;
        _hidden = NO;
        _deleted = NO;
        _selected = NO;
        _windowType = type;
        _expanded = NO;
        mOldVisible = NO;
        mMoveable = YES;
        _stateDict = [[idDict alloc] init];
        _variableDict = [[idDict alloc] init];
        _scriptDict = [[idDict alloc] init];

        if ( [window isKindOfClass:[idEditWindow class]] ) {
            _windowType = WT_EDIT;
        } else if ( [window isKindOfClass:[idListWindow class]] ) {
            _windowType = WT_LIST;
        } else if ( [window isKindOfClass:[idBindWindow class]] ) {
            _windowType = WT_BIND;
        } else if ( [window isKindOfClass:[idRenderWindow class]] ) {
            _windowType = WT_RENDER;
        } else if ( [window isKindOfClass:[idChoiceWindow class]] ) {
            _windowType = WT_CHOICE;
        } else if ( [window isKindOfClass:[idSliderWindow class]] ) {
            // not in the engine, which wrote a sliderDef back as a windowDef
            // though it has WT_SLIDER and its name
            _windowType = WT_SLIDER;
        } else {
            _windowType = WT_NORMAL;
        }

        // Attach the wrapper to the window (the engine's "guied_wrapper" var)
        window->guiedWrapper = self;

        [self setStateKey:@"name" value:[window getName] update:NO];
    }
    return self;
}

/// idWindowEditorWrapper's: the window's parse wraps it so.
- (instancetype)initForWindow:(idWindow *)window {
    return [self initWithWindow:window type:WT_NORMAL];
}

/*
================
rvGEWindowWrapper::GetWrapper

Static method that returns the window wrapper for the given window class
================
*/
+ (rvGEWindowWrapper *)wrapperOf:(idWindow *)window {
    return window != nil ? (rvGEWindowWrapper *)window->guiedWrapper : nil;
}

- (idRectangle)clientRect {
    return mClientRect;
}

- (idRectangle)screenRect {
    return mScreenRect;
}

/*
================
rvGEWindowWrapper::UpdateRect

Updates the gui editor's representation of the window rectangle from the
windows rectangle
================
*/
- (void)updateRect {
    idWindow *window = self.window;
    idWinRectangle *winrect = (idWinRectangle *)[window getWinVarByName:@"rect"];
    NSAssert([winrect isKindOfClass:[idWinRectangle class]], @"a window's rect");
    idVec4 rect = [winrect toVec4];

    _flippedHorz = NO;
    _flippedVert = NO;

    if ( rect.z < 0 ) {
        _flippedHorz = YES;
        rect.z *= -1;
    }

    if ( rect.w < 0 ) {
        _flippedVert = YES;
        rect.w *= -1;
    }

    mClientRect = idRectangle_FromVec4( rect );

    [self calcScreenRect];

    NSString *rstr = [_stateDict getString:@"rect" defaultString:@"0,0,0,0"];
    mMoveable = !rvGE_IsExpression( rstr );
}

/*
================
rvGEWindowWrapper::CalcScreenRect

Calculates the screen rectangle from the client rectangle by running through
the parent windows and adding their offsets
================
*/
- (void)calcScreenRect {
    idWindow *parent;

    mScreenRect = mClientRect;

    if ( nil != (parent = [self.window getParent]) ) {
        rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:parent];
        NSAssert(wrapper, @"a wrapped window's parent is wrapped");

        mScreenRect.x += wrapper.screenRect.x;
        mScreenRect.y += wrapper.screenRect.y;
    }

    // Since our screen rectangle has changed we need to tell all our our children to update
    // their screen rectangles as well.
    int i;
    int count;
    rvGEWindowWrapper *pwrapper;

    pwrapper = [rvGEWindowWrapper wrapperOf:self.window];

    for ( count = [pwrapper childCount], i = 0; i < count; i ++ ) {
        rvGEWindowWrapper *wrapper;

        wrapper = [rvGEWindowWrapper wrapperOf:[pwrapper childAtIndex:i]];

        // Usually we assert if there is no wrapper but since this method is called
        // when the wrappers are being attached to the windows there may be no wrappers
        // for any of the children.
        if ( !wrapper ) {
            continue;
        }

        [wrapper calcScreenRect];
    }
}

/*
================
rvGEWindowWrapper::SetRect

Sets the wrapper's rectangle and the attached windows rectangle as well
================
*/
- (void)setRect:(idRectangle)rect {
    mClientRect = rect;
    [self calcScreenRect];

    NSString *s = [NSString stringWithFormat:@"%d,%d,%d,%d", (int) (rect.x + 0.5f), (int) (rect.y + 0.5f),
                   (int) ((rect.w + 0.5f) * (_flippedHorz ? -1 : 1)), (int) ((rect.h + 0.5f) * (_flippedVert ? -1 : 1))];

    [_stateDict set:@"rect" value:s];

    [self updateWindowState];
}

/*
================
rvGEWindowWrapper::SetHidden

Sets the wrappers hidden state
================
*/
- (void)setHidden:(BOOL)h {
    _hidden = h;

    [self updateWindowState];
}

/*
================
rvGEWindowWrapper::SetDeleted

Sets the deleted state of the wrapper which in turns sets whether or
not the window is visible
================
*/
- (void)setDeleted:(BOOL)del {
    _deleted = del;

    [self updateWindowState];
}

/*
================
rvGEWindowWrapper::SetState

Sets the window state from the given dictionary
================
*/
- (void)setState:(idDict *)dict {
    [_stateDict clear];
    for ( int i = 0; i < [dict numKeyVals]; i++ ) {
        [_stateDict set:[dict keyAtIndex:i] value:[dict valueAtIndex:i]];
    }

    // Push the window state to the window itself
    [self updateWindowState];

    // Update the internal rectangle since it may have changed in the state
    [self updateRect];
}

/*
================
rvGEWindowWrapper::SetStateKey

Sets the given state key and updates the
================
*/
- (void)setStateKey:(NSString *)key value:(NSString *)value update:(BOOL)update {
    [_stateDict set:key value:value];

    if ( update ) {
        [self updateWindowState];

        // Make sure the rectangle gets updated if its changing
        if ( [key ud_iequals:@"rect"] ) {
            [self updateRect];
        }
    }
}

/*
================
rvGEWindowWrapper::DeleteStateKey

Sets the given state key and updates the
================
*/
- (void)deleteStateKey:(NSString *)key {
    if ( [key ud_iequals:@"rect"] || [key ud_iequals:@"name"] ) {
        return;
    }

    [_stateDict deleteKey:key];
}

/*
================
rvGEWindowWrapper::UpdateWindowState

Updates the windows real state with wrappers internal state.  Visibility is
handled specially
================
*/
- (void)updateWindowState {
    NSString *realVisible;
    BOOL tempVisible;

    realVisible = [_stateDict getString:@"visible" defaultString:@"1"];
    tempVisible = atoi( realVisible.UTF8String ) ? YES : NO;
    if ( tempVisible != mOldVisible ) {
        _hidden = !tempVisible;
        mOldVisible = tempVisible;
    }

    tempVisible = !_deleted && !_hidden;

    // Temporarily change the visible state so we can hide/unhide the window
    [_stateDict set:@"visible" value:tempVisible ? @"1" : @"0"];

    [self.window updateFromDictionary:_stateDict];

    // Put the visible state back to the real value
    [_stateDict set:@"visible" value:realVisible];
}

/*
================
rvGEWindowWrapper::WindowFromPoint

Returns the topmost window under the given point
================
*/
- (idWindow *)windowFromPointX:(float)x y:(float)y visibleOnly:(BOOL)visibleOnly {
    return [self windowFromPointX:x y:y visibleOnly:visibleOnly passing:nil];
}

- (idWindow *)windowFromPointX:(float)x y:(float)y visibleOnly:(BOOL)visibleOnly passing:(NSSet<idWindow *> *)passed {
    int count;
    int i;
    rvGEWindowWrapper *pwrapper;

    // If the window isnt visible then skip it
    if ( visibleOnly && (_hidden || _deleted) ) {
        return nil;
    }
    // (not the engine's: the windows the editor passes through)
    if ( visibleOnly && [passed containsObject:self.window] ) {
        return nil;
    }

    // Now check our children next
    pwrapper = [rvGEWindowWrapper wrapperOf:self.window];
    count = [pwrapper childCount];

    for ( i = count - 1; i >= 0; i -- ) {
        rvGEWindowWrapper *wrapper;
        idWindow *child;

        child = [pwrapper childAtIndex:i];
        NSAssert(child, @"a child");

        wrapper = [rvGEWindowWrapper wrapperOf:child];
        if ( !wrapper ) {
            continue;
        }

        // (the engine's call leaves visibleOnly to its default, true)
        if ( (child = [wrapper windowFromPointX:x y:y visibleOnly:YES passing:passed]) ) {
            return child;
        }
    }

    // We have to check this last because a child could be out outside of the parents
    // rectangle and we still want it selectable.
    if ( !idRectangle_Contains( &mScreenRect, x, y ) ) {
        return nil;
    }

    return self.window;
}

/*
================
rvGEWindowWrapper::StringToWindowType

Converts the given string to a window type
================
*/
+ (rvGEWindowType)windowTypeFromString:(NSString *)string {
    if ( [string ud_iequals:@"windowDef"] ) {
        return WT_NORMAL;
    } else if ( [string ud_iequals:@"editDef"] ) {
        return WT_EDIT;
    } else if ( [string ud_iequals:@"choiceDef"] ) {
        return WT_CHOICE;
    } else if ( [string ud_iequals:@"sliderDef"] ) {
        return WT_SLIDER;
    } else if ( [string ud_iequals:@"bindDef"] ) {
        return WT_BIND;
    } else if ( [string ud_iequals:@"listDef"] ) {
        return WT_LIST;
    } else if ( [string ud_iequals:@"renderDef"] ) {
        return WT_RENDER;
    } else if ( [string ud_iequals:@"htmlDef"] ) {
        return WT_HTML;
    }

    return WT_UNKNOWN;
}

/*
================
rvGEWindowWrapper::WindowTypeToString

Converts the given window type to a string
================
*/
+ (NSString *)stringFromWindowType:(rvGEWindowType)type {
    static NSString *const typeNames[] = {
        @"Unknown", @"windowDef", @"editDef", @"htmlDef", @"choiceDef", @"sliderDef", @"bindDef", @"listDef", @"renderDef"
    };
    if ( (int)type < 0 || (int)type >= (int)(sizeof(typeNames) / sizeof(typeNames[0])) ) {
        return typeNames[0];
    }
    return typeNames[(int) type];
}

/*
================
rvGEWindowWrapper::GetChildCount

Returns the number of children the window being wrapped has
================
*/
- (int)childCount {
    if ( ![self canHaveChildren] ) {
        return 0;
    }

    return [self.window getChildCount];
}

- (idWindow *)childAtIndex:(int)index {
    return [self.window getChild:index];
}

/*
================
rvGEWindowWrapper::CanHaveChildren

Returns true if the window is allowed to have child windows
================
*/
- (BOOL)canHaveChildren {
    if ( _windowType == WT_HTML || _windowType == WT_LIST ) {
        return NO;
    }

    return YES;
}

- (BOOL)canMoveAndSize {
    return mMoveable;
}

/*
================
rvGEWindowWrapper::GetDepth

Returns the depth of the wrapped window
================
*/
- (int)depth {
    idWindow *parent;
    int depth;

    for ( depth = 0, parent = [self.window getParent]; parent; parent = [parent getParent], depth++ )
        ;

    return depth;
}

/*
================
rvGEWindowWrapper::Expand

Expand the window in the navigator and all of its parents too
================
*/
- (BOOL)expand {
    BOOL result;

    if ( [self.window getParent] ) {
        result = [[rvGEWindowWrapper wrapperOf:[self.window getParent]] expand];
    } else {
        result = NO;
    }

    if ( _expanded || ![self canHaveChildren] || ![self childCount] ) {
        return result;
    }

    _expanded = YES;

    return YES;
}

/*
================
rvGEWindowWrapper::Collapse

Returns the depth of the wrapped window
================
*/
- (BOOL)collapse {
    BOOL result;

    if ( [self.window getParent] ) {
        result = [[rvGEWindowWrapper wrapperOf:[self.window getParent]] expand];
    } else {
        result = NO;
    }

    if ( !_expanded ) {
        return result;
    }

    _expanded = NO;

    return YES;
}

/*
================
rvGEWindowWrapper::Finish

After a the windwo wrapper is attached to a window and the window is parsed
the finish method is called to finish up any last details
================
*/
- (void)finish {
    mOldVisible = ((idWinBool *)[self.window getWinVarByName:@"visible"]).data;
    _hidden = mOldVisible ? NO : YES;
    [self updateRect];
}

/*
================
rvGEWindowWrapper::VerfiyStateKey

Verifies that the given state key value is valid for the given key
================
*/
- (BOOL)verifyStateKey:(NSString *)name value:(NSString *)value result:(NSString **)result {
    idWindow *window = self.window;
    NSString *old;
    BOOL failed;

    NSData *bytes __attribute__((objc_precise_lifetime)) = [value ud_latin1Buffer];
    // the engine's parser throws on an error; this one says so (its
    // diagnostics, given before the text is loaded, its lexer's)
    idParser *src = [[idParser alloc] initWithFlags:LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWMULTICHARLITERALS | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                         fileSystem:nil];
    NSMutableArray<NSDictionary *> *diagnostics = [NSMutableArray array];
    src.diagnostics = diagnostics;
    [src loadMemory:bytes.bytes length:(int)bytes.length - 1 name:@"" error:NULL];

    // Save the current value
    old = [_stateDict getString:name];
    failed = NO;

    // Try to parse in the value
    if ( ![window parseInternalVar:name parser:src] ) {
        // Kill the old register since the parse reg entry will add a new one
        if ( ![window parseRegEntry:name parser:src] ) {
            failed = YES;
        }
    }
    for ( NSDictionary *d in diagnostics ) {
        if ( [d[@"error"] boolValue] ) {
            failed = YES;
        }
    }

    // Restore the old value
    NSData *oldBytes __attribute__((objc_precise_lifetime)) = [old ud_latin1Buffer];
    idParser *src2 = [[idParser alloc] initWithBuffer:oldBytes.bytes length:(int)oldBytes.length - 1 name:@""
                                                flags:LEXFL_NOFATALERRORS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWMULTICHARLITERALS | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                                error:NULL];
    if ( ![window parseInternalVar:name parser:src2] ) {
        if ( ![window parseRegEntry:name parser:src2] ) {
        }
    }

    // Check to see if the old value matches the new value
    NSCharacterSet *white = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *before = UDStripTrailing( value, white );
    NSMutableString *after = [NSMutableString string];
    [src stringFromMarker:after clean:NO error:NULL];
    NSString *afterStripped = UDStripTrailing( after, white );

    if ( result ) {
        *result = afterStripped;
    }

    if ( failed || ![before isEqualToString:afterStripped] ) {
        return NO;
    }

    return YES;
}

@end

/*
================
StringFromVec4

Returns a clean string version of the given vec4
================
*/
NSString *rvGE_StringFromVec4(idVec4 v) {
    return [NSString stringWithFormat:@"%@,%@,%@,%@",
            idStr_FloatArrayToString( &v.x, 1, 8 ),
            idStr_FloatArrayToString( &v.y, 1, 8 ),
            idStr_FloatArrayToString( &v.z, 1, 8 ),
            idStr_FloatArrayToString( &v.w, 1, 8 )];
}

/// idStr::StripQuotes
NSString *rvGE_StripQuotes(NSString *s) {
    if ( ![s hasPrefix:@"\""] ) {
        return s;
    }
    NSUInteger end = s.length;
    // Remove the trailing quote first
    if ( end > 1 && [s characterAtIndex:end - 1] == '"' ) {
        end--;
    }
    // Strip the leading quote now
    return [s substringWithRange:NSMakeRange(1, end - 1)];
}

/*
================
IsExpression

Returns true if the given string is an expression
================
*/
BOOL rvGE_IsExpression(NSString *s) {
    NSData *bytes __attribute__((objc_precise_lifetime)) = [s ud_latin1Buffer];
    idParser *src = [[idParser alloc] initWithBuffer:bytes.bytes length:(int)bytes.length - 1 name:@""
                                               flags:LEXFL_ALLOWMULTICHARLITERALS |
                                                     LEXFL_NOSTRINGCONCAT |
                                                     LEXFL_ALLOWBACKSLASHSTRINGCONCAT |
                                                     LEXFL_NOFATALERRORS
                                               error:NULL];

    idToken token;
    idToken_Init( &token );
    BOOL needComma = NO;
    BOOL needNumber = NO;
    while ( [src readToken:&token error:NULL] ) {
        switch ( token.type ) {
            case TT_NUMBER:
                needComma = YES;
                needNumber = NO;
                break;

            case TT_PUNCTUATION:
                if ( needNumber ) {
                    return YES;
                }
                if ( token.text[0] == ',' ) {
                    if ( !needComma ) {
                        return YES;
                    }

                    needComma = NO;
                    break;
                }

                if ( needComma ) {
                    return YES;
                }

                if ( token.text[0] == '-' ) {
                    needNumber = YES;
                }
                break;

            default:
                return YES;
        }
    }

    return NO;
}
