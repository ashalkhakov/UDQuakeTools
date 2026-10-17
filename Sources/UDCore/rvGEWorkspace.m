/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEWorkspace.m — tools/guied/GEWorkspace.cpp and GEWorkspaceFile.cpp,
 * ported (the file's half here; the window's in Decl Browser).
 */

#import "rvGEWorkspace.h"
#import "rvGEWindowWrapper.h"
#import "idUserInterface.h"
#import "idWindow.h"
#import "idDict.h"
#import "idLexer.h"
#import "idStr.h"

@interface rvGEWorkspace ()
@property (nonatomic, strong, readwrite, nullable) idUserInterfaceLocal *interface;
@end

@implementation rvGEWorkspace

- (instancetype)initWithManager:(idUserInterfaceManager *)manager {
    self = [super init];
    if (self) {
        _manager = manager;
        manager.editing = YES;
    }
    return self;
}

/*
================
rvGEWorkspace::LoadFile

Loads the given gui file.
================
*/
- (BOOL)loadFile:(NSString *)qpath {
    return [self _load:nil path:qpath];
}

- (BOOL)loadText:(NSString *)text path:(NSString *)qpath {
    return [self _load:text path:qpath];
}

- (BOOL)_load:(nullable NSString *)text path:(NSString *)qpath {
    if (self.interface != nil) {
        [self.manager deAlloc:self.interface];
    }

    // Let the real window system parse it first (the engine's FindGui of a
    // copy, unique: a GUI of its own, not the cache's)
    idUserInterfaceLocal *gui = [self.manager allocGui];
    BOOL result = text != nil ? [gui initFromText:text path:qpath] : [gui initFromFile:qpath];
    self.interface = gui;

    if ( result ) {
        [[rvGEWindowWrapper wrapperOf:[gui getDesktop]] expand];
    }

    return result;
}

- (NSString *)text {
    NSMutableString *out = [NSMutableString string];
    idWindow *window = [self.interface getDesktop];
    if (window != nil) {
        [self writeWindow:window depth:1 into:out];
    }
    return out;
}

/*
================
rvGEWorkspace::WriteTabs

Writes the given number of tabs to the given file
================
*/
static void WriteTabs( NSMutableString *file, int depth ) {
    int i;

    for ( i = 0; i < depth; i ++ ) {
        [file appendString:@"\t"];
    }
}

/*
================
rvGEWorkspace::WriteWindow

Writes the contents of the given window to the file
================
*/
- (void)writeWindow:(idWindow *)window depth:(int)depth into:(NSMutableString *)file {
    rvGEWindowWrapper *wrapper;
    int i;

    wrapper = [rvGEWindowWrapper wrapperOf:window];
    if ( !wrapper ) {
        return;
    }

    if ( wrapper.deleted ) {
        return;
    }

    // Window def header
    WriteTabs( file, depth - 1 );

    [file appendString:[rvGEWindowWrapper stringFromWindowType:wrapper.windowType]];
    [file appendString:@" "];

    [file appendString:[window getName]];
    [file appendString:@"\r\n"];

    WriteTabs( file, depth - 1 );

    [file appendString:@"{\r\n"];

    idDict *state = wrapper.stateDict;
    for ( i = 0; i < [state numKeyVals]; i ++ ) {
        NSString *key = [state keyAtIndex:i];

        // Dont write name to the files
        if ( [key ud_iequals:@"name"] ) {
            continue;
        }

        WriteTabs( file, depth );

        [file appendString:key];
        [file appendString:@"\t"];

        NSString *value = [state valueAtIndex:i];
        for ( NSUInteger p = 0; p < value.length; p ++ ) {
            unichar c = [value characterAtIndex:p];
            switch ( c ) {
                case '\n':
                    [file appendString:@"\\n"];
                    break;

                default:
                    [file appendFormat:@"%C", c];
                    break;
            }
        }

        [file appendString:@"\r\n"];
    }

    idDict *variables = wrapper.variableDict;
    for ( i = 0; i < [variables numKeyVals]; i ++ ) {
        WriteTabs( file, depth );

        [file appendString:[variables keyAtIndex:i]];
        [file appendString:@"\t"];
        [file appendString:[variables valueAtIndex:i]];
        [file appendString:@"\r\n"];
    }

    idDict *scripts = wrapper.scriptDict;
    if ( [scripts numKeyVals] ) {
        [file appendString:@"\r\n"];
    }

    for ( i = 0; i < [scripts numKeyVals]; i ++ ) {
        WriteTabs( file, depth );

        [file appendString:[scripts keyAtIndex:i]];
        [file appendString:@" "];

        NSData *bytes __attribute__((objc_precise_lifetime)) = [[scripts valueAtIndex:i] ud_latin1Buffer];
        idLexer *src = [[idLexer alloc] initWithBuffer:bytes.bytes length:(int)bytes.length - 1 name:@""
                                                 flags:LEXFL_ALLOWMULTICHARLITERALS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                            fileSystem:nil error:NULL];
        NSMutableString *out = [NSMutableString string];
        [src parseBracedSectionExact:out tabs:depth + 1 skippingCommentsAndStrings:YES error:NULL];

        [file appendString:out];
        [file appendString:@"\r\n"];
        [file appendString:@"\r\n"];
    }

    for ( i = 0; i < [wrapper childCount]; i ++ ) {
        idWindow *child = [wrapper childAtIndex:i];

        [self writeWindow:child depth:depth + 1 into:file];
    }

    // Window def footer
    WriteTabs( file, depth - 1 );

    [file appendString:@"}\r\n"];
}

@end
