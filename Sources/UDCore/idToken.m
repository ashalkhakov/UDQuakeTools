/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDToken.h — token type
 */

#import "idToken.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <assert.h>
#include <stdbool.h>

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

void idToken_Init(idToken *token) {
    memset(token, 0, sizeof(idToken));
    token->text[0] = '\0';
    token->length = 0;
    token->floatvalue = 0.0;
}

void idToken_InitWithToken(idToken *token, const idToken *other) {
    idToken_AssignFromToken(token, other);
}

void idToken_BuiltinLine(idToken *token, const idToken *deftoken) {
    snprintf(token->text, MAX_TOKEN_CHARS, "%d", deftoken->line);
    token->length = (int)strlen(token->text);
    
    token->intvalue = deftoken->line;
    token->floatvalue = deftoken->line;
    token->type = TT_NUMBER;
    token->subtype = TT_DECIMAL | TT_INTEGER | TT_VALUESVALID;
    token->line = deftoken->line;
    token->linesCrossed = deftoken->linesCrossed;
    token->flags = 0;
}

void idToken_BuiltinFile(idToken *token, const char *fileName, const idToken *deftoken) {
    strlcpy(token->text, fileName, MAX_TOKEN_CHARS);
    token->length = (int)strlen(token->text);
    
    token->type = TT_NAME;
    token->subtype = token->length;
    token->line = deftoken->line;
    token->linesCrossed = deftoken->linesCrossed;
    token->flags = 0;
}

void idToken_BuiltinDate(idToken *token, const idToken *deftoken) {
    time_t t = time(NULL);
    struct tm *tm_info = localtime(&t);
    
    // "%b %e %Y" formats as "MMM dd yyyy" with space-padding for single-digit days
    char buffer[32];
    strftime(buffer, sizeof(buffer), "\"%b %e %Y\"", tm_info);
    
    strlcpy(token->text, buffer, MAX_TOKEN_CHARS);
    token->length = (int)strlen(token->text);
    
    token->type = TT_STRING;
    token->subtype = token->length;
    token->line = deftoken->line;
    token->linesCrossed = deftoken->linesCrossed;
    token->flags = 0;
}

void idToken_BuiltinTime(idToken *token, const idToken *deftoken) {
    time_t t = time(NULL);
    struct tm *tm_info = localtime(&t);
    
    // "%H:%M:%S" formats as 24-hour, zero-padded time
    char buffer[32];
    strftime(buffer, sizeof(buffer), "\"%H:%M:%S\"", tm_info);
    
    strlcpy(token->text, buffer, MAX_TOKEN_CHARS);
    token->length = (int)strlen(token->text);
    
    token->type = TT_STRING;
    token->subtype = token->length;
    token->line = deftoken->line;
    token->linesCrossed = deftoken->linesCrossed;
    token->flags = 0;
}

void idToken_AssignFromToken(idToken *token, const idToken *other) {
    // Because the struct is flat, we can just do a direct memory copy
    *token = *other;
}

void idToken_AssignFromString(idToken *token, const char *text) {
    strlcpy(token->text, text, MAX_TOKEN_CHARS);
    token->length = (int)strlen(token->text);
}

void idToken_AssignFromInt(idToken *token, signed int value) {
    snprintf(token->text, MAX_TOKEN_CHARS, "%d", abs(value));
    token->length = (int)strlen(token->text);
    
    token->type = TT_NUMBER;
    token->subtype = TT_INTEGER | TT_LONG | TT_DECIMAL | TT_VALUESVALID;
    token->intvalue = abs(value);
    token->floatvalue = abs(value);
}

void idToken_AssignFromFloat(idToken *token, float value) {
    snprintf(token->text, MAX_TOKEN_CHARS, "%1.2f", fabs(value));
    token->length = (int)strlen(token->text);
    
    token->type = TT_NUMBER;
    token->subtype = TT_FLOAT | TT_LONG | TT_DECIMAL | TT_VALUESVALID;
    token->intvalue = (unsigned int)fabs(value);
    token->floatvalue = fabs(value);
}

void idToken_Clear(idToken *token) {
    token->text[0] = '\0';
    token->length = 0;
}

const char * idToken_String(const idToken *token) {
    return token->text;
}

void idToken_CopyFromBuffer(idToken *token, const char *p, int length) {
    if (length >= MAX_TOKEN_CHARS) {
        length = MAX_TOKEN_CHARS - 1;
    }
    memcpy(token->text, p, length);
    token->text[length] = '\0';
    token->length = length;
}

int idToken_Type(const idToken *token) {
    return token->type;
}

void idToken_SetType(idToken *token, int type) {
    token->type = type;
}

int idToken_Subtype(const idToken *token) {
    return token->subtype;
}

void idToken_SetSubtype(idToken *token, int subtype) {
    token->subtype = subtype;
}

void idToken_AddToSubtype(idToken *token, int subtypeBits) {
    token->subtype |= subtypeBits;
}

void idToken_SetTypeNumber(idToken *token) {
    token->type = TT_NUMBER;
    token->subtype = 0;
    token->intvalue = 0;
    token->floatvalue = 0;
}

void idToken_SetWhitespaceStart(idToken *token, const char *start) {
    token->whiteSpaceStart_p = start;
}

void idToken_SetWhitespaceEnd(idToken *token, const char *end, int line, int linesCrossed) {
    token->whiteSpaceEnd_p = end;
    token->line = line;
    token->linesCrossed = linesCrossed;
    token->flags = 0;
}

double idToken_DoubleValue(const idToken *token) {
    if (token->type != TT_NUMBER) {
        return 0.0;
    }
    if (!(token->subtype & TT_VALUESVALID)) {
        idToken_NumberValue((idToken *)token); // Cast away const to cache values
    }
    return token->floatvalue;
}

float idToken_FloatValue(const idToken *token) {
    return (float)idToken_DoubleValue(token);
}

unsigned int idToken_UnsignedIntValue(const idToken *token) {
    if (token->type != TT_NUMBER) {
        return 0;
    }
    if (!(token->subtype & TT_VALUESVALID)) {
        idToken_NumberValue((idToken *)token);
    }
    return token->intvalue;
}

int idToken_IntValue(const idToken *token) {
    return (int)idToken_UnsignedIntValue(token);
}

int idToken_WhiteSpaceBeforeToken(const idToken *token) {
    return (token->whiteSpaceEnd_p > token->whiteSpaceStart_p);
}

void idToken_ClearTokenWhiteSpace(idToken *token) {
    token->whiteSpaceStart_p = NULL;
    token->whiteSpaceEnd_p = NULL;
    token->linesCrossed = 0;
}

void idToken_ClearTokenWhiteSpaceButNotLinesCrossed(idToken *token) {
    token->whiteSpaceStart_p = NULL;
    token->whiteSpaceEnd_p = NULL;
}

void idToken_AppendDirty(idToken *token, char a) {
    if (a == '\\') {
        a = '/';
    }
    if (token->length < MAX_TOKEN_CHARS - 1) {
        token->text[token->length] = a;
        token->length++;
        token->text[token->length] = '\0';
    }
}

void idToken_AppendToken(idToken *token, const idToken *other) {
    strlcat(token->text, other->text, MAX_TOKEN_CHARS);
    token->length = (int)strlen(token->text);
}

void idToken_ZeroTerminate(idToken *token) {
    // NOP - text is constantly kept zero-terminated
}

unsigned int idToken_Length(const idToken *token) {
    return token->length;
}

void idToken_SetSubtypeFromLength(idToken *token) {
    token->subtype = token->length;
}

void idToken_SetSubtypeFromFirstChar(idToken *token) {
    token->subtype = token->text[0];
}

void idToken_NumberValue(idToken *token) {
    int i, pow, div, c;
    const char *p;
    double m;

    assert(token->type == TT_NUMBER);
    p = token->text;
    token->floatvalue = 0;
    token->intvalue = 0;
    
    // floating point number
    if (token->subtype & TT_FLOAT) {
        if (token->subtype & (TT_INFINITE | TT_INDEFINITE | TT_NAN)) {
            if (token->subtype & TT_INFINITE) {            // 1.#INF
                unsigned int inf = 0x7f800000;
                token->floatvalue = (double)*(float *)&inf;
            } else if (token->subtype & TT_INDEFINITE) {   // 1.#IND
                unsigned int ind = 0xffc00000;
                token->floatvalue = (double)*(float *)&ind;
            } else if (token->subtype & TT_NAN) {          // 1.#QNAN
                unsigned int nan = 0x7fc00000;
                token->floatvalue = (double)*(float *)&nan;
            }
        } else {
            while (*p && *p != '.' && *p != 'e') {
                token->floatvalue = token->floatvalue * 10.0 + (double)(*p - '0');
                p++;
            }
            if (*p == '.') {
                p++;
                for (m = 0.1; *p && *p != 'e'; p++) {
                    token->floatvalue = token->floatvalue + (double)(*p - '0') * m;
                    m *= 0.1;
                }
            }
            if (*p == 'e') {
                p++;
                if (*p == '-') {
                    div = true;
                    p++;
                } else if (*p == '+') {
                    div = false;
                    p++;
                } else {
                    div = false;
                }
                pow = 0;
                for (pow = 0; *p; p++) {
                    pow = pow * 10 + (int)(*p - '0');
                }
                for (m = 1.0, i = 0; i < pow; i++) {
                    m *= 10.0;
                }
                if (div) {
                    token->floatvalue /= m;
                } else {
                    token->floatvalue *= m;
                }
            }
        }
        token->intvalue = (unsigned int)token->floatvalue;
    } else if (token->subtype & TT_DECIMAL) {
        while (*p) {
            token->intvalue = token->intvalue * 10 + (*p - '0');
            p++;
        }
        token->floatvalue = token->intvalue;
    } else if (token->subtype & TT_IPADDRESS) {
        c = 0;
        while (*p && *p != ':') {
            if (*p == '.') {
                while (c != 3) {
                    token->intvalue = token->intvalue * 10;
                    c++;
                }
                c = 0;
            } else {
                token->intvalue = token->intvalue * 10 + (*p - '0');
                c++;
            }
            p++;
        }
        while (c != 3) {
            token->intvalue = token->intvalue * 10;
            c++;
        }
        token->floatvalue = token->intvalue;
    } else if (token->subtype & TT_OCTAL) {
        // step over the first zero
        p += 1;
        while (*p) {
            token->intvalue = (token->intvalue << 3) + (*p - '0');
            p++;
        }
        token->floatvalue = token->intvalue;
    } else if (token->subtype & TT_HEX) {
        // step over the leading 0x or 0X
        p += 2;
        while (*p) {
            token->intvalue <<= 4;
            if (*p >= 'a' && *p <= 'f')
                token->intvalue += *p - 'a' + 10;
            else if (*p >= 'A' && *p <= 'F')
                token->intvalue += *p - 'A' + 10;
            else
                token->intvalue += *p - '0';
            p++;
        }
        token->floatvalue = token->intvalue;
    } else if (token->subtype & TT_BINARY) {
        // step over the leading 0b or 0B
        p += 2;
        while (*p) {
            token->intvalue = (token->intvalue << 1) + (*p - '0');
            p++;
        }
        token->floatvalue = token->intvalue;
    }
    token->subtype |= TT_VALUESVALID;
}

int idToken_Line(const idToken *token) {
    return token->line;
}

void idToken_SetLine(idToken *token, int line) {
    token->line = line;
}

int idToken_LinesCrossed(const idToken *token) {
    return token->linesCrossed;
}

void idToken_AddToLinesCrossed(idToken *token, int amount) {
    token->linesCrossed += amount;
}

idToken * idToken_Next(const idToken *token) {
    return token->next;
}

void idToken_SetNext(idToken *token, idToken *next) {
    token->next = next;
}

const char * idToken_WhiteSpaceStart(const idToken *token) {
    return token->whiteSpaceStart_p;
}

const char * idToken_WhiteSpaceEnd(const idToken *token) {
    return token->whiteSpaceEnd_p;
}

int idToken_Flags(const idToken *token) {
    return token->flags;
}

void idToken_AddToFlags(idToken *token, int flags) {
    token->flags |= flags;
}

void idToken_StripQuotes(idToken *token) {
    if (token->text[0] != '\"')
    {
        return;
    }

    // Remove the trailing quote first
    if (token->text[token->length-1] == '\"')
    {
        token->text[token->length-1] = '\0';
        token->length--;
    }

    // Strip the leading quote now
    token->length--;
    memmove(&token->text[0], &token->text[1], token->length);
    token->text[token->length] = '\0';
}
