/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclRawText.m — the decls edited as text: materials, articulated figures, models, exports.
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

#pragma mark - DeclMaterial (raw text only)

@implementation UDDeclMaterial

+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"{\n"
        @"\t\t"        @"blend\tblend\n"
        @"\t\t"        @"map\t\t_default\n"
        @"\t"    @"}\n"
        @"}";
}

@end

#pragma mark - Raw text only, until their editors arrive



// idDeclAF::DefaultDefinition
@implementation UDDeclAF

+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"settings {\n"
        @"\t\t"        @"model \"\"\n"
        @"\t\t"        @"skin \"\"\n"
        @"\t\t"        @"friction 0.01, 0.01, 0.8, 0.5\n"
        @"\t\t"        @"suspendSpeed 20, 30, 40, 60\n"
        @"\t\t"        @"noMoveTime 1\n"
        @"\t\t"        @"noMoveTranslation 10\n"
        @"\t\t"        @"noMoveRotation 10\n"
        @"\t\t"        @"minMoveTime -1\n"
        @"\t\t"        @"maxMoveTime -1\n"
        @"\t\t"        @"totalMass -1\n"
        @"\t\t"        @"contents corpse\n"
        @"\t\t"        @"clipMask solid, corpse\n"
        @"\t\t"        @"selfCollision 1\n"
        @"\t"    @"}\n"
        @"\t"    @"body \"body\" {\n"
        @"\t\t"        @"joint \"origin\"\n"
        @"\t\t"        @"mod orientation\n"
        @"\t\t"        @"model box( ( -10, -10, -10 ), ( 10, 10, 10 ) )\n"
        @"\t\t"        @"origin ( 0, 0, 0 )\n"
        @"\t\t"        @"density 0.2\n"
        @"\t\t"        @"friction 0.01, 0.01, 0.8\n"
        @"\t\t"        @"contents corpse\n"
        @"\t\t"        @"clipMask solid, corpse\n"
        @"\t\t"        @"selfCollision 1\n"
        @"\t\t"        @"containedJoints \"*origin\"\n"
        @"\t"    @"}\n"
        @"}\n";
}

@end

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
