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
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Doom 3 Source Code. If not, see <http://www.gnu.org/licenses/>.

In addition, the Doom 3 Source Code is also subject to certain additional terms. You should have received a copy of these additional terms immediately following the terms and conditions of the GNU General Public License which accompanied the Doom 3 Source Code. If not, please request a copy in writing from id Software at the address below.

If you have questions concerning this license or the applicable additional terms, you may contact in writing id Software LLC, c/o ZeniMax Media Inc., Suite 120, Rockville, Maryland 20850 USA.

===========================================================================
*/

#import <Foundation/Foundation.h>

#ifndef FILE_HASH_SIZE
#define FILE_HASH_SIZE        1024
#endif

// make str_t a multiple of 16 bytes long
// don't make too large to keep memory requirements to a minimum
#define STR_ALLOC_BASE 20
#define STR_ALLOC_GRAN 32

typedef struct {
    int     len;
    char    *data;
    int     alloced;
    char    baseBuffer[STR_ALLOC_BASE];
} idStr;

static inline void idStr_Init(idStr *self) {
    self->len = 0;
    self->alloced = STR_ALLOC_BASE;
    self->data = self->baseBuffer;
    self->data[0] = '\0';
#ifdef ID_DEBUG_UNINITIALIZED_MEMORY
    memset(baseBuffer, 0, sizeof(baseBuffer));
#endif
}

static inline char* idStr_GetString(idStr *self) {
    return self->data;
}

static inline void idStr_ReAllocate(idStr *self, int amount, BOOL keepold) {
    char* newbuffer;
    int    newsize;
    int    mod;

    //assert( self->data );
    assert( amount > 0 );

    mod = amount % STR_ALLOC_GRAN;
    if ( !mod ) {
        newsize = amount;
    } else {
        newsize = amount + STR_ALLOC_GRAN - mod;
    }
    self->alloced = newsize;

    if (self->data && self->data != self->baseBuffer) {
        char *olddata = self->data;
        self->data = (char *)malloc(newsize);
        memcpy(self->data, olddata, self->len);
        free(olddata);
    } else {
        newbuffer = (char *)malloc(newsize);
        if (self->data && keepold) {
            memcpy(newbuffer, self->data, self->len);
            newbuffer[self->len] = '\0';
        } else {
            newbuffer[0] = '\0';
        }
        self->data = newbuffer;
    }
}

static inline void idStr_Free(idStr *self) {
    if (self->data && self->data != self->baseBuffer) {
        free(self->data);
        self->data = self->baseBuffer;
        self->data[0] = '\0';
    }
}

static inline void idStr_EnsureAlloced(idStr *self, int amount, BOOL keepold) {
    if (amount > self->alloced) {
        idStr_ReAllocate(self, amount, keepold);
    }
}

static inline void idStr_InitFromStr(idStr *self, const idStr *text) {
    int l;

    idStr_Init(self);
    l = text->len;
    idStr_EnsureAlloced(self, l + 1, NO);
    strcpy(self->data, text->data);
    self->len = l;
}

static inline void idStr_CopyFrom(idStr *self, const idStr *text) {
    if (text == self) {
        return;
    }

    int l;

    l = text->len;
    idStr_EnsureAlloced(self, l + 1, NO);
    memcpy(self->data, text->data, l);
    self->data[l] = '\0';
    self->len = l;
}

static inline int idStr_Allocated(const idStr *self) {
    if (self->data == self->baseBuffer) {
        return 0;
    }
    return self->alloced;
}

static inline void idStr_AppendChar(idStr *self, const char a) {
    idStr_EnsureAlloced(self, self->len + 2, YES);
    self->data[self->len] = a;
    self->len++;
    self->data[self->len ] = '\0';
}

static inline void idStr_Append(idStr *self, const char *text) {
    int newLen;
    int i;

    if (!text) {
        return;
    }

    newLen = self->len + (int)strlen(text);
    idStr_EnsureAlloced(self, newLen + 1, YES);
    for (i = 0; text[i]; i++) {
        self->data[self->len + i] = text[i];
    }
    self->len = newLen;
    self->data[self->len] = '\0';
}

static inline void idStr_AppendLength(idStr *self, const char *text, int l) {
    int newLen;
    int i;

    if (text && l) {
        newLen = self->len + l;
        idStr_EnsureAlloced(self, newLen + 1, YES);
        for (i = 0; text[i] && i < l; i++) {
            self->data[self->len + i] = text[i];
        }
        self->len = newLen;
        self->data[self->len] = '\0';
    }
}

// case sensitive compare
int idStr_Cmp(const idStr *self, const char *text);
int idStr_Cmpn(const idStr *self, const char *text, int n);
int idStr_CmpPrefix(const idStr *self, const char *text);

// case insensitive compare
int idStr_Icmp(const idStr *self, const char *text);
int idStr_Icmpn(const idStr *self, const char *text, int n);

static inline int idStr_IcmpPrefix(const idStr *self, const char *text) {
    return idStr_Icmpn(self, text, strlen(text));
}

// compares paths and makes sure folders come first
int idStr_IcmpPath(const idStr *self, const char *text);
int idStr_IcmpnPath(const idStr *self, const char *text, int n);

static inline int idStr_IcmpPrefixPath(const idStr *self, const char *text) {
    return idStr_IcmpnPath(self, text, strlen(text));
}

static inline void idStr_Clear(idStr *self) {
    idStr_Free(self);
    idStr_Init(self);
}

static inline void idStr_Empty(idStr *self) {
    idStr_EnsureAlloced(self, 1, NO);
    self->data[0] = '\0';
    self->len = 0;
}

static inline void idStr_ToLower(idStr *self) {
    for (int i = 0; self->data[i]; i++ ) {
        int c = self->data[i];
        if ((c <= 'Z' && c >= 'A') || (c >= 0xC0 && c <= 0xDF)) {
            self->data[i] += ( 'a' - 'A' );
        }
    }
}

static inline void idStr_CapLength(idStr *self, int newlen) {
    if (self->len <= newlen) {
        return;
    }
    self->data[newlen] = 0;
    self->len = newlen;
}

int idStr_FindChar(const idStr *self, const char c, int start, int end);
int idStr_FindString(const idStr *self, const char *text, BOOL casesensitive, int start, int end);

const char *idStr_Mid(const idStr *self, int start, int len, idStr *result);    // store 'len' characters starting at 'start' in result

// store the leftmost 'len' characters in the result
static inline const char *idStr_Left(const idStr *self, int len, idStr *result) {
    return idStr_Mid(self, 0, len, result);
}

// store the rightmost 'len' characters in the result
static inline const char *idStr_Right(const idStr *self, int len, idStr *result) {
    if (len >= self->len) {
        idStr_CopyFrom(result, self);
        return result->data;
    }
    return idStr_Mid(self, self->len - len, len, result);
}


void idStr_StripLeadingChar(idStr *self, const char c);                    // strip char from front as many times as the char occurs
void idStr_StripLeadingStr(idStr *self, const char *string);                // strip string from front as many times as the string occurs
BOOL idStr_StripLeadingOnce(idStr *self, const char *string);            // strip string from front just once if it occurs
void idStr_StripTrailingChar(idStr *self, const char c);                    // strip char from end as many times as the char occurs
void idStr_StripTrailingStr(idStr *self, const char *string);            // strip string from end as many times as the string occurs
BOOL idStr_StripTrailingOnce(idStr *self, const char *string);        // strip string from end just once if it occurs

// strip char from front and end as many times as the char occurs
static inline void idStr_StripChar(idStr *self, const char c) {
    idStr_StripLeadingChar(self, c);
    idStr_StripTrailingChar(self, c);
}

// strip string from front and end as many times as the string occurs
static inline void idStr_StripStr(idStr *self, const char *string) {
    idStr_StripLeadingStr(self, string);
    idStr_StripTrailingStr(self, string);
}

void idStr_StripTrailingWhitespace(idStr *self);                // strip trailing white space characters
void idStr_StripQuotes(idStr *self);                            // strip quotes around string

int idStr_Replace(idStr *self, const char *old, const char *nw);

// file methods
void idStr_StripQuotes(idStr *self);                            // strip quotes around string
int idStr_Replace(idStr *self, const char *old, const char *nw);

// file name methods
int idStr_FileNameHash(const idStr *self);                        // hash key for the filename (skips extension)
void idStr_BackSlashesToSlashes(idStr *self);                    // convert slashes
void idStr_SetFileExtension(idStr *self, const char *extension);        // set the given file extension
void idStr_StripFileExtension(idStr *self);                        // remove any file extension
void idStr_StripAbsoluteFileExtension(idStr *self);                // remove any file extension looking from front (useful if there are multiple .'s)
void idStr_DefaultFileExtension(idStr *self, const char *extension);    // if there's no file extension use the default
void idStr_DefaultPath(idStr *self, const char *basepath);            // if there's no path use the default
void idStr_AppendPath(idStr *self, const char *text);                    // append a partial path
void idStr_StripFilename(idStr *self);                            // remove the filename from a path
void idStr_StripPath(idStr *self);                                // remove the path from the filename
void idStr_ExtractFilePath(const idStr *self, idStr *dest);            // copy the file path to another string
void idStr_ExtractFileName(const idStr *self, idStr *dest);            // copy the filename to another string
void idStr_ExtractFileBase(const idStr *self, idStr *dest);            // copy the filename minus the extension to another string
void idStr_ExtractFileExtension(const idStr *self, idStr *dest);        // copy the file extension to another string
BOOL idStr_CheckExtension(const idStr *self, const char *ext);

static inline void idStr_Insert(idStr *self, const char *text, int index) {
    int i, l;

    if (index < 0) {
        index = 0;
    } else if (index > self->len) {
        index = self->len;
    }

    l = (int)strlen(text);
    idStr_EnsureAlloced(self, self->len + l + 1, YES);
    for (i = self->len; i >= index; i--) {
        self->data[i+l] = self->data[i];
    }
    for (i = 0; i < l; i++) {
        self->data[index+i] = text[i];
    }
    self->len += l;
}

BOOL idStr_HasUpper(const idStr *self);
void idStr_Copynz(char *dest, const char *src, int destsize);

int idStr_snPrintf(char *dest, int size, const char *fmt, ...);
int idStr_vsnPrintf(char *dest, int size, const char *fmt, va_list argptr);

/*
 idStr::Filter

 Returns true if the string conforms the given filter.
 Several metacharacter may be used in the filter.

 *          match any string of zero or more characters
 ?          match any single character
 [abc...]   match any of the enclosed characters; a hyphen can
            be used to specify a range (e.g. a-z, A-Z, 0-9)
 */
BOOL idStr_Filter(const char *filter, const char *name, BOOL casesensitive);
