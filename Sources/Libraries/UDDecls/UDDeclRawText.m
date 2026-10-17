/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclRawText.m — the decls edited as text: models, exports.
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclRawText.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

#pragma mark - Raw text only, until their editors arrive




// idDeclModelDef::DefaultDefinition
@implementation UDDeclModel

+ (NSString *)ud_defaultDefinition {
    return @"{ }";
}

@end

// An export is a plain idDecl: idDeclLocal::DefaultDefinition.
@implementation UDDeclExport

+ (NSString *)ud_defaultDefinition {
    return @"{ }";
}

@end
