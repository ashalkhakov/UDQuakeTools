/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDToken.h — token type
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, UDIdTokenKind) {
    UDIdTokenKindEOF = 0,
    UDIdTokenKindIdentifier,
    UDIdTokenKindString,
    UDIdTokenKindPunctuation,
};

@interface UDIdToken : NSObject

@property (nonatomic, assign) UDIdTokenKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) NSUInteger start;
@property (nonatomic, assign) NSUInteger end;

@end

/*
===========================================================================

Doom 3 GPL Source Code
Copyright (C) 1999-2011 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 GPL Source Code ("Doom 3 Source Code").

Doom 3 Source Code is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Doom 3 Source Code is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Doom 3 Source Code.  If not, see <http://www.gnu.org/licenses/>.

In addition, the Doom 3 Source Code is also subject to certain additional terms. You should have received a copy of these additional terms immediately following the terms and conditions of the GNU General Public License which accompanied the Doom 3 Source Code.  If not, please request a copy in writing from id Software at the address below.

If you have questions concerning this license or the applicable additional terms, you may contact in writing id Software LLC, c/o ZeniMax Media Inc., Suite 120, Rockville, Maryland 20850 USA.

===========================================================================
*/

/*
===============================================================================

    idToken is a token read from a file or memory with idLexer or idParser

===============================================================================
*/

// token types
#define TT_STRING                    1        // string
#define TT_LITERAL                    2        // literal
#define TT_NUMBER                    3        // number
#define TT_NAME                        4        // name
#define TT_PUNCTUATION                5        // punctuation

// number sub types
#define TT_INTEGER                    0x00001        // integer
#define TT_DECIMAL                    0x00002        // decimal number
#define TT_HEX                        0x00004        // hexadecimal number
#define TT_OCTAL                    0x00008        // octal number
#define TT_BINARY                    0x00010        // binary number
#define TT_LONG                        0x00020        // long int
#define TT_UNSIGNED                    0x00040        // unsigned int
#define TT_FLOAT                    0x00080        // floating point number
#define TT_SINGLE_PRECISION            0x00100        // float
#define TT_DOUBLE_PRECISION            0x00200        // double
#define TT_EXTENDED_PRECISION        0x00400        // long double
#define TT_INFINITE                    0x00800        // infinite 1.#INF
#define TT_INDEFINITE                0x01000        // indefinite 1.#IND
#define TT_NAN                        0x02000        // NaN
#define TT_IPADDRESS                0x04000        // ip address
#define TT_IPPORT                    0x08000        // ip port
#define TT_VALUESVALID                0x10000        // set if intvalue and floatvalue are valid

// string sub type is the length of the string
// literal sub type is the ASCII code
// punctuation sub type is the punctuation id
// name sub type is the length of the name

// Maximum characters a single token can hold (adjust as needed for your parser)
#define MAX_TOKEN_CHARS         1024

// The flat C-struct replacing the Objective-C class
typedef struct idToken_s {
    char                text[MAX_TOKEN_CHARS]; // Replaces NSMutableString
    int                 length;                // Replaces [NSMutableString length]
    
    int                 type;                  // token type
    int                 subtype;               // token sub type
    int                 line;                  // line in script the token was on
    int                 linesCrossed;          // number of lines crossed in white space before token
    int                 flags;                 // token flags, used for recursive defines
    
    unsigned int        intvalue;              // integer value
    double              floatvalue;            // floating point value
    const char * whiteSpaceStart_p;     // start of white space before token
    const char * whiteSpaceEnd_p;       // end of white space before token
    
    struct idToken_s * next;                  // next token in chain
} idToken;


// ----------------------------------------------------------------------------
// Function Prototypes (Replacing Objective-C Methods)
// ----------------------------------------------------------------------------

void            idToken_Init(idToken *token);
void            idToken_InitWithToken(idToken *token, const idToken *other);

const char * idToken_String(const idToken *token);

void            idToken_BuiltinLine(idToken *token, const idToken *deftoken);
void            idToken_BuiltinFile(idToken *token, const char *fileName, const idToken *deftoken);
void            idToken_BuiltinDate(idToken *token, const idToken *deftoken);
void            idToken_BuiltinTime(idToken *token, const idToken *deftoken);

void            idToken_AssignFromToken(idToken *token, const idToken *other);
void            idToken_AssignFromString(idToken *token, const char *text);
void            idToken_AssignFromInt(idToken *token, signed int intvalue);
void            idToken_AssignFromFloat(idToken *token, float floatvalue);

void            idToken_CopyFromBuffer(idToken *token, const char *p, int length);

void            idToken_Clear(idToken *token);

int             idToken_Type(const idToken *token);
void            idToken_SetType(idToken *token, int type);

int             idToken_Subtype(const idToken *token);
void            idToken_SetSubtype(idToken *token, int subtype);
void            idToken_AddToSubtype(idToken *token, int subtypeBits);

void            idToken_SetTypeNumber(idToken *token);

void            idToken_SetWhitespaceStart(idToken *token, const char *start);
void            idToken_SetWhitespaceEnd(idToken *token, const char *end, int line, int linesCrossed);

double          idToken_DoubleValue(const idToken *token);
float           idToken_FloatValue(const idToken *token);
unsigned int    idToken_UnsignedIntValue(const idToken *token);
int             idToken_IntValue(const idToken *token);

int             idToken_WhiteSpaceBeforeToken(const idToken *token);
void            idToken_ClearTokenWhiteSpace(idToken *token);
void            idToken_ClearTokenWhiteSpaceButNotLinesCrossed(idToken *token);

void            idToken_NumberValue(idToken *token);

unsigned int    idToken_Length(const idToken *token);

void            idToken_AppendDirty(idToken *token, char a);
void            idToken_ZeroTerminate(idToken *token);
void            idToken_AppendToken(idToken *token, const idToken *other);

void            idToken_SetSubtypeFromLength(idToken *token);
void            idToken_SetSubtypeFromFirstChar(idToken *token);

int             idToken_Line(const idToken *token);
void            idToken_SetLine(idToken *token, int line);
int             idToken_LinesCrossed(const idToken *token);
void            idToken_AddToLinesCrossed(idToken *token, int amount);

idToken * idToken_Next(const idToken *token);
void            idToken_SetNext(idToken *token, idToken *next);

const char * idToken_WhiteSpaceStart(const idToken *token);
const char * idToken_WhiteSpaceEnd(const idToken *token);

int             idToken_Flags(const idToken *token);
void            idToken_AddToFlags(idToken *token, int flags);

void idToken_StripQuotes(idToken *token);
