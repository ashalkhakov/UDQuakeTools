#import "idStr.h"

#define INTSIGNBITSET(i)        (((const unsigned int)(i)) >> 31)
#define INTSIGNBITNOTSET(i)        ((~((const unsigned int)(i))) >> 31)

int idStr_Cmp(const idStr *self, const char *s2) {
    int c1, c2, d;
    
    const char *s1 = self->data;

    do {
        c1 = *s1++;
        c2 = *s2++;

        d = c1 - c2;
        if (d) {
            return (INTSIGNBITNOTSET(d) << 1) - 1;
        }
    } while (c1);

    return 0;        // strings are equal
}

static int cmpn(const char *s1, const char *s2, int n) {
    int c1, c2, d;
    
    assert(n >= 0);
    do {
        c1 = *s1++;
        c2 = *s2++;

        if (!n--) {
            return 0;        // strings are equal until end point
        }

        d = c1 - c2;
        if (d) {
            return (INTSIGNBITNOTSET(d) << 1) - 1;
        }
    } while (c1);

    return 0;        // strings are equal
}


int idStr_Cmpn(const idStr *self, const char *s2, int n) {
    return cmpn(self->data, s2, n);
}

int idStr_Icmp(const idStr *self, const char *s2) {
    int c1, c2, d;
    
    const char *s1 = self->data;

    do {
        c1 = *s1++;
        c2 = *s2++;

        d = c1 - c2;
        while (d) {
            if (c1 <= 'Z' && c1 >= 'A') {
                d += ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            if (c2 <= 'Z' && c2 >= 'A') {
                d -= ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            return (INTSIGNBITNOTSET(d) << 1) - 1;
        }
    } while (c1);

    return 0;        // strings are equal
}

int idStr_Icmpn(const idStr *self, const char *s2, int n) {
    int c1, c2, d;

    assert(n >= 0);
    const char *s1 = self->data;

    do {
        c1 = *s1++;
        c2 = *s2++;

        if (!n--) {
            return 0;        // strings are equal until end point
        }

        d = c1 - c2;
        while (d) {
            if (c1 <= 'Z' && c1 >= 'A') {
                d += ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            if (c2 <= 'Z' && c2 >= 'A') {
                d -= ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            return (INTSIGNBITNOTSET(d) << 1) - 1;
        }
    } while (c1);

    return 0;        // strings are equal
}

int idStr_IcmpPath(const idStr *self, const char *s2) {
    int c1, c2, d;
    
    const char *s1 = self->data;

    do {
        c1 = *s1++;
        c2 = *s2++;

        d = c1 - c2;
        while (d) {
            if (c1 <= 'Z' && c1 >= 'A') {
                d += ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            if (c1 == '\\') {
                d += ('/' - '\\');
                if (!d) {
                    break;
                }
            }
            if (c2 <= 'Z' && c2 >= 'A') {
                d -= ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            if (c2 == '\\') {
                d -= ('/' - '\\');
                if (!d) {
                    break;
                }
            }
            // make sure folders come first
            while (c1) {
                if (c1 == '/' || c1 == '\\') {
                    break;
                }
                c1 = *s1++;
            }
            while (c2) {
                if (c2 == '/' || c2 == '\\') {
                    break;
                }
                c2 = *s2++;
            }
            if (c1 && !c2) {
                return -1;
            } else if (!c1 && c2) {
                return 1;
            }
            // same folder depth so use the regular compare
            return (INTSIGNBITNOTSET(d) << 1) - 1;
        }
    } while (c1);

    return 0;
}

int idStr_IcmpnPath(const idStr *self, const char *s2, int n) {
    int c1, c2, d;
    
    const char *s1 = self->data;

    assert(n >= 0);

    do {
        c1 = *s1++;
        c2 = *s2++;

        if (!n--) {
            return 0;        // strings are equal until end point
        }

        d = c1 - c2;
        while (d) {
            if (c1 <= 'Z' && c1 >= 'A') {
                d += ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            if (c1 == '\\') {
                d += ('/' - '\\');
                if (!d) {
                    break;
                }
            }
            if (c2 <= 'Z' && c2 >= 'A') {
                d -= ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            if (c2 == '\\') {
                d -= ('/' - '\\');
                if (!d) {
                    break;
                }
            }
            // make sure folders come first
            while (c1) {
                if (c1 == '/' || c1 == '\\') {
                    break;
                }
                c1 = *s1++;
            }
            while (c2) {
                if (c2 == '/' || c2 == '\\') {
                    break;
                }
                c2 = *s2++;
            }
            if (c1 && !c2) {
                return -1;
            } else if (!c1 && c2) {
                return 1;
            }
            // same folder depth so use the regular compare
            return (INTSIGNBITNOTSET(d) << 1) - 1;
        }
    } while (c1);

    return 0;
}

int idStr_FindChar(const idStr *self, const char c, int start, int end) {
    int i;
    
    const char *str = self->data;

    if (end == -1) {
        end = (int)strlen(str) - 1;
    }
    for (i = start; i <= end; i++) {
        if (str[i] == c) {
            return i;
        }
    }
    return -1;
}

int idStr_FindString(const idStr *self, const char *text, BOOL casesensitive, int start, int end) {
    int l, i, j;
    
    const char *str = self->data;

    if (end == -1) {
        end = (int)strlen(str);
    }
    l = end - (int)strlen(text);
    for (i = start; i <= l; i++) {
        if (casesensitive) {
            for (j = 0; text[j]; j++) {
                if (str[i+j] != text[j]) {
                    break;
                }
            }
        } else {
            for (j = 0; text[j]; j++) {
                if (toupper(str[i+j]) != toupper(text[j])) {
                    break;
                }
            }
        }
        if (!text[j]) {
            return i;
        }
    }
    return -1;
}

const char *idStr_Mid(const idStr *self, int start, int len, idStr *result) {
    int i;

    idStr_Empty(result);

    i = self->len;
    if (i == 0 || len <= 0 || start >= i) {
        return NULL;
    }

    if (start + len >= i) {
        len = i - start;
    }

    idStr_AppendLength(result, &self->data[start], self->len);
    return result->data;
}

void idStr_StripLeadingChar(idStr *self, const char c) {
    while (self->data[0] == c) {
        memmove(&self->data[0], &self->data[1], self->len);
        self->len--;
    }
}

void idStr_StripLeadingStr(idStr *self, const char *string) {
    int l;

    l = (int)strlen(string);
    if (l > 0) {
        while (!idStr_Cmpn(self, string, l)) {
            memmove(self->data, self->data + l, self->len - l + 1);
            self->len -= l;
        }
    }
}

BOOL idStr_StripLeadingOnce(idStr *self, const char *string) {
    int l;

    l = (int)strlen(string);
    if ((l > 0) && !idStr_Cmpn(self, string, l) ) {
        memmove(self->data, self->data + l, self->len - l + 1);
        self->len -= l;
        return YES;
    }
    return NO;
}

void idStr_StripTrailingChar(idStr *self, const char c) {
    int i;
    
    for (i = self->len; i > 0 && self->data[i - 1] == c; i--) {
        self->data[i - 1] = '\0';
        self->len--;
    }
}

void idStr_StripTrailingStr(idStr *self, const char *string) {
    int l;

    l = (int)strlen(string);
    if (l > 0) {
        while ((self->len >= l) && !cmpn(string, self->data + self->len - l, l)) {
            self->len -= l;
            self->data[self->len] = '\0';
        }
    }
}

BOOL idStr_StripTrailingOnce(idStr *self, const char *string) {
    int l;

    l = (int)strlen(string);
    if ((l > 0) && (self->len >= l) && !cmpn(string, self->data + self->len - l, l)) {
        self->len -= l;
        self->data[self->len] = '\0';
        return YES;
    }
    return NO;
}

void idStr_StripTrailingWhitespace(idStr *self) {
    int i;
    
    // cast to unsigned char to prevent stripping off high-ASCII characters
    for (i = self->len; i > 0 && (unsigned char)(self->data[i - 1]) <= ' '; i--) {
        self->data[i - 1] = '\0';
        self->len--;
    }
}

void idStr_StripQuotes(idStr *self) {
    if (!self->len) {
        return;
    }

    if (self->data[0] != '\"')
    {
        return;
    }
    
    // Remove the trailing quote first
    if (self->data[self->len-1] == '\"')
    {
        self->data[self->len-1] = '\0';
        self->len--;
    }

    // Strip the leading quote now
    self->len--;
    memmove(&self->data[0], &self->data[1], self->len);
    self->data[self->len] = '\0';
}

int idStr_Replace(idStr *self, const char *old, const char *nw) {
    int        iReplaced = 0;
    int        oldLen, newLen, i, j, count;
    idStr      oldString;
    
    idStr_InitFromStr(&oldString, self);

    oldLen = (int)strlen(old);
    newLen = (int)strlen(nw);

    // Work out how big the new string will be
    count = 0;
    for (i = 0; i < oldString.len; i++) {
        if (!cmpn(&oldString.data[i], old, oldLen)) {
            count++;
            i += oldLen - 1;
        }
    }

    if (count) {
        idStr_EnsureAlloced(self, self->len + ((newLen - oldLen) * count) + 2, NO);

        // Replace the old data with the new data
        for (i = 0, j = 0; i < oldString.len; i++) {
            if(!cmpn(&oldString.data[i], old, oldLen)) {
                memcpy(self->data + j, nw, newLen);
                i += oldLen - 1;
                j += newLen;
                iReplaced++;
            } else {
                self->data[j] = oldString.data[i];
                j++;
            }
        }
        self->data[j] = 0;
        self->len = (int)strlen(self->data);
    }
    return iReplaced;
}

static inline char toLower(char c) {
    if (c <= 'Z' && c >= 'A') {
        return (c + ('a' - 'A'));
    }
    return c;
}

int idStr_FileNameHash(const idStr *self) {
    int        i;
    long    hash;
    char    letter;

    hash = 0;
    i = 0;
    while (self->data[i] != '\0') {
        letter = toLower(self->data[i]);
        if (letter == '.') {
            break;                // don't include extension
        }
        if (letter =='\\') {
            letter = '/';
        }
        hash += (long)(letter)*(i+119);
        i++;
    }
    hash &= (FILE_HASH_SIZE-1);
    return (int)hash;
}

void idStr_BackSlashesToSlashes(idStr *self) {
    int i;

    for (i = 0; i < self->len; i++) {
        if (self->data[i] == '\\') {
            self->data[i] = '/';
        }
    }
}

void idStr_SetFileExtension(idStr *self, const char *extension) {
    idStr_StripFileExtension(self);
    if (*extension != '.') {
        idStr_AppendChar(self, '.');
    }
    idStr_Append(self, extension);
}

void idStr_StripFileExtension(idStr *self) {
    int i;

    for (i = self->len-1; i >= 0; i--) {
        if (self->data[i] == '.') {
            self->data[i] = '\0';
            self->len = i;
            break;
        }
    }
}

void idStr_StripAbsoluteFileExtension(idStr *self) {
    int i;

    for (i = 0; i < self->len; i++) {
        if (self->data[i] == '.') {
            self->data[i] = '\0';
            self->len = i;
            break;
        }
    }

}

void idStr_DefaultFileExtension(idStr *self, const char *extension) {
    int i;

    // do nothing if the string already has an extension
    for (i = self->len-1; i >= 0; i--) {
        if (self->data[i] == '.') {
            return;
        }
    }
    if (*extension != '.') {
        idStr_AppendChar(self, '.');
    }
    idStr_Append(self, extension);
}

void idStr_DefaultPath(idStr *self, const char *basepath) {
    if ((self->data[0] == '/') || (self->data[0] == '\\')) {
        // absolute path location
        return;
    }

    idStr_Insert(self, basepath, 0);
}

void idStr_AppendPath(idStr *self, const char *text) {
    int pos;
    int i = 0;

    if (text && text[i]) {
        pos = self->len;
        idStr_EnsureAlloced(self, self->len + (int)strlen(text) + 2, YES);

        if (pos) {
            if (self->data[pos-1] != '/' ) {
                self->data[pos++] = '/';
            }
        }
        if (text[i] == '/') {
            i++;
        }

        for ( ; text[i]; i++) {
            if (text[i] == '\\') {
                self->data[pos++] = '/';
            } else {
                self->data[pos++] = text[i];
            }
        }
        self->len = pos;
        self->data[pos] = '\0';
    }
}

void idStr_StripFilename(idStr *self) {
    int pos;

    pos = self->len - 1;
    while ((pos > 0) && (self->data[pos] != '/') && (self->data[pos] != '\\')) {
        pos--;
    }

    if (pos < 0) {
        pos = 0;
    }

    idStr_CapLength(self, pos);
}

void idStr_StripPath(idStr *self) {
    int pos;

    pos = self->len;
    while ((pos > 0) && (self->data[pos - 1] != '/') && (self->data[pos - 1] != '\\')) {
        pos--;
    }
    
    idStr tmp;
    idStr_Init(&tmp);
    idStr_Right(self, self->len - pos, &tmp);
    idStr_CopyFrom(self, &tmp);
    idStr_Free(&tmp);
}

void idStr_ExtractFilePath(const idStr *self, idStr *dest) {
    int pos;

    //
    // back up until a \ or the start
    //
    pos = self->len;
    while ((pos > 0) && (self->data[pos - 1] != '/') && (self->data[pos - 1] != '\\')) {
        pos--;
    }

    idStr_Left(self, pos, dest);
}

void idStr_ExtractFileName(const idStr *self, idStr *dest) {
    int pos;

    //
    // back up until a \ or the start
    //
    pos = self->len - 1;
    while ((pos > 0) && (self->data[pos - 1] != '/') && (self->data[pos - 1] != '\\')) {
        pos--;
    }

    idStr_Right(self, self->len - pos, dest);
}

void idStr_ExtractFileBase(const idStr *self, idStr *dest) {
    int pos;
    int start;

    //
    // back up until a \ or the start
    //
    pos = self->len - 1;
    while ((pos > 0) && (self->data[pos - 1] != '/') && (self->data[pos - 1] != '\\')) {
        pos--;
    }

    start = pos;
// RAVEN BEGIN
// jscott: for getting the file base out of addnormals() style filenames
    while ((pos < self->len) && (self->data[pos] != '.') && (self->data[pos] != ',')) {
// RAVEN END
        pos++;
    }

    idStr_Mid(self, start, pos - start, dest);
}

void idStr_ExtractFileExtension(const idStr *self, idStr *dest) {
    int pos;

    //
    // back up until a . or the start
    //
    pos = self->len - 1;
    while ((pos > 0) && (self->data[pos - 1] != '.')) {
        pos--;
    }

    if (!pos) {
        // no extension
        idStr_Empty(dest);
    } else {
        idStr_Right(self, self->len - pos, dest);
    }
}

BOOL idStr_CheckExtension(const idStr *self, const char *ext) {
    const char *name = self->data;
    const int nameLen = self->len;
    const char *s1 = name + nameLen - 1;
    const char *s2 = ext + strlen(ext) - 1;
    int c1, c2, d;

    do {
        c1 = *s1--;
        c2 = *s2--;

        d = c1 - c2;
        while (d) {
            if (c1 <= 'Z' && c1 >= 'A') {
                d += ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            if (c2 <= 'Z' && c2 >= 'A') {
                d -= ('a' - 'A');
                if (!d) {
                    break;
                }
            }
            return NO;
        }
    } while (s1 > name && s2 > ext);

    return (s1 >= name);
}

BOOL idStr_HasUpper(const idStr *self) {
    if (!self) {
        return NO;
    }
    
    const char *s = self->data;
    
    while (*s) {
        int c = *s;
        if (c >= 'A' && c <= 'Z') { // FIXME: what about other languages?
            return YES;
        }
        s++;
    }
    
    return NO;
}

void idStr_Copynz(char *dest, const char *src, int destsize) {
    if ( !src ) {
        //idLib::common->Warning( "idStr::Copynz: NULL src" );
        return;
    }
    if ( destsize < 1 ) {
        //idLib::common->Warning( "idStr::Copynz: destsize < 1" );
        return;
    }

    strncpy(dest, src, destsize-1);
    dest[destsize-1] = 0;
}

// behaves like C99's vsnprintf() by returning the amount of bytes that
// *would* have been written into a big enough buffer, even if that's > size
// unlike idStr::vsnPrintf() which returns -1 in that case
int D3_vsnprintfC99(char *dst, size_t size, const char *format, va_list ap)
{
    // before VS2015, it didn't have a standards-conforming (v)snprintf()-implementation
    // same might be true for other windows compilers if they use old CRT versions, like MinGW does
#if defined(_WIN32) && (!defined(_MSC_VER) || _MSC_VER < 1900)
  #undef _vsnprintf
    // based on DG_vsnprintf() from https://github.com/DanielGibson/Snippets/blob/master/DG_misc.h
    int ret = -1;
    if(dst != NULL && size > 0)
    {
#if defined(_MSC_VER) && _MSC_VER >= 1400
        // I think MSVC2005 introduced _vsnprintf_s().
        // this shuts up _vsnprintf() security/deprecation warnings.
        ret = _vsnprintf_s(dst, size, _TRUNCATE, format, ap);
#else
        ret = _vsnprintf(dst, size, format, ap);
        dst[size-1] = '\0'; // ensure '\0'-termination
#endif
    }

    if(ret == -1)
    {
        // _vsnprintf() returns -1 if the output is truncated
        // it's also -1 if dst or size were NULL/0, so the user didn't want to write
        // we want to return the number of characters that would've been
        // needed, though.. fortunately _vscprintf() calculates that.
        ret = _vscprintf(format, ap);
    }
    return ret;
  #define _vsnprintf    use_idStr_vsnPrintf
#else // other operating systems and VisualC++ >= 2015 should have a proper vsnprintf()
  #undef vsnprintf
    return vsnprintf(dst, size, format, ap);
  #define vsnprintf    use_idStr_vsnPrintf
#endif
}

// behaves like C99's snprintf() by returning the amount of bytes that
// *would* have been written into a big enough buffer, even if that's > size
// unlike idStr::snPrintf() which returns the written bytes in that case
// and also calls common->Warning() in case of overflows
int D3_snprintfC99(char *dst, size_t size, const char *format, ...)
{
    int ret = 0;
    va_list argptr;
    va_start( argptr, format );
    ret = D3_vsnprintfC99(dst, size, format, argptr);
    va_end( argptr );
    return ret;
}

int idStr_snPrintf(char *dest, int size, const char *fmt, ...) {
    va_list argptr;
    int len;
    va_start( argptr, fmt );
    len = D3_vsnprintfC99(dest, size, fmt, argptr);
    va_end( argptr );
    /*
    if ( len >= 32000 ) {
        // TODO: Previously this function used a 32000 byte buffer to write into
        //       with vsprintf(), and raised this error if that was overflowed
        //       (more likely that'd have lead to a crash..).
        //       Technically we don't have that restriction anymore, so I'm unsure
        //       if this error should really still be raised to preserve
        //       the old intended behavior, maybe for compat with mod DLLs using
        //       the old version of the function or something?
        //idLib::common->Error( "idStr::snPrintf: overflowed buffer" );
    }*/
    if ( len >= size ) {
        NSLog(@"idStr_snPrintf: overflow of %i in %i\n", len, size);
        len = size;
    }
    return len;
}

int idStr_vsnPrintf( char *dest, int size, const char *fmt, va_list argptr ) {
    int ret = D3_vsnprintfC99(dest, size, fmt, argptr);
    if ( ret < 0 || ret >= size ) {
        return -1;
    }
    return ret;
}

BOOL idStr_Filter(const char *filter, const char *name, BOOL casesensitive) {
    idStr buf;
    int i, found, index;

    idStr_Init(&buf);

    while (*filter) {
        if (*filter == '*') {
            filter++;
            idStr_Empty(&buf);
            for (i = 0; *filter; i++) {
                if (*filter == '*' || *filter == '?' || (*filter == '[' && *(filter+1) != '[')) {
                    break;
                }
                idStr_AppendChar(&buf, *filter);
                if (*filter == '[') {
                    filter++;
                }
                filter++;
            }
            if (buf.len) {
                idStr tmp;
                idStr_Init(&tmp);
                idStr_Append(&tmp, name);
                
                index = idStr_FindString(&tmp, buf.data, casesensitive, 0, -1);
                if (index == -1) {
                    idStr_Free(&tmp);
                    idStr_Free(&buf);
                    return NO;
                }
                name += index + strlen(buf.data);
                idStr_Free(&tmp);
            }
        } else if (*filter == '?') {
            filter++;
            name++;
        } else if (*filter == '[') {
            if (*(filter+1) == '[') {
                if (*name != '[') {
                    idStr_Free(&buf);
                    return NO;
                }
                filter += 2;
                name++;
            } else {
                filter++;
                found = NO;
                while (*filter && !found) {
                    if (*filter == ']' && *(filter+1) != ']') {
                        break;
                    }
                    if (*(filter+1) == '-' && *(filter+2) && (*(filter+2) != ']' || *(filter+3) == ']')) {
                        if (casesensitive) {
                            if (*name >= *filter && *name <= *(filter+2)) {
                                found = YES;
                            }
                        } else {
                            if (toupper(*name) >= toupper(*filter) && toupper(*name) <= toupper(*(filter+2))) {
                                found = YES;
                            }
                        }
                        filter += 3;
                    } else {
                        if (casesensitive) {
                            if (*filter == *name) {
                                found = YES;
                            }
                        } else {
                            if (toupper(*filter) == toupper(*name) ) {
                                found = YES;
                            }
                        }
                        filter++;
                    }
                }
                if (!found) {
                    idStr_Free(&buf);
                    return NO;
                }
                while (*filter) {
                    if (*filter == ']' && *(filter+1) != ']') {
                        break;
                    }
                    filter++;
                }
                filter++;
                name++;
            }
        } else {
            if (casesensitive) {
                if (*filter != *name) {
                    idStr_Free(&buf);
                    return NO;
                }
            } else {
                if (toupper(*filter) != toupper(*name)) {
                    idStr_Free(&buf);
                    return NO;
                }
            }
            filter++;
            name++;
        }
    }
    idStr_Free(&buf);
    return YES;
}
