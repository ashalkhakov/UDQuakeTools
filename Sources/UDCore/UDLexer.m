#import "UDLexer.h"
#import "idFile.h"
#import "idFileSystem.h"

#define PUNCTABLE

//longer punctuations first
punctuation_t default_punctuations[] = {
    //binary operators
    {">>=",P_RSHIFT_ASSIGN},
    {"<<=",P_LSHIFT_ASSIGN},
    //
    {"...",P_PARMS},
    //define merge operator
    {"##",P_PRECOMPMERGE},                // pre-compiler
    //logic operators
    {"&&",P_LOGIC_AND},                    // pre-compiler
    {"||",P_LOGIC_OR},                    // pre-compiler
    {">=",P_LOGIC_GEQ},                    // pre-compiler
    {"<=",P_LOGIC_LEQ},                    // pre-compiler
    {"==",P_LOGIC_EQ},                    // pre-compiler
    {"!=",P_LOGIC_UNEQ},                // pre-compiler
    //arithmatic operators
    {"*=",P_MUL_ASSIGN},
    {"/=",P_DIV_ASSIGN},
    {"%=",P_MOD_ASSIGN},
    {"+=",P_ADD_ASSIGN},
    {"-=",P_SUB_ASSIGN},
    {"++",P_INC},
    {"--",P_DEC},
    //binary operators
    {"&=",P_BIN_AND_ASSIGN},
    {"|=",P_BIN_OR_ASSIGN},
    {"^=",P_BIN_XOR_ASSIGN},
    {">>",P_RSHIFT},                    // pre-compiler
    {"<<",P_LSHIFT},                    // pre-compiler
    //reference operators
    {"->",P_POINTERREF},
    //C++
    {"::",P_CPP1},
    {".*",P_CPP2},
    //arithmatic operators
    {"*",P_MUL},                        // pre-compiler
    {"/",P_DIV},                        // pre-compiler
    {"%",P_MOD},                        // pre-compiler
    {"+",P_ADD},                        // pre-compiler
    {"-",P_SUB},                        // pre-compiler
    {"=",P_ASSIGN},
    //binary operators
    {"&",P_BIN_AND},                    // pre-compiler
    {"|",P_BIN_OR},                        // pre-compiler
    {"^",P_BIN_XOR},                    // pre-compiler
    {"~",P_BIN_NOT},                    // pre-compiler
    //logic operators
    {"!",P_LOGIC_NOT},                    // pre-compiler
    {">",P_LOGIC_GREATER},                // pre-compiler
    {"<",P_LOGIC_LESS},                    // pre-compiler
    //reference operator
    {".",P_REF},
    //seperators
    {",",P_COMMA},                        // pre-compiler
    {";",P_SEMICOLON},
    //label indication
    {":",P_COLON},                        // pre-compiler
    //if statement
    {"?",P_QUESTIONMARK},                // pre-compiler
    //embracements
    {"(",P_PARENTHESESOPEN},            // pre-compiler
    {")",P_PARENTHESESCLOSE},            // pre-compiler
    {"{",P_BRACEOPEN},                    // pre-compiler
    {"}",P_BRACECLOSE},                    // pre-compiler
    {"[",P_SQBRACKETOPEN},
    {"]",P_SQBRACKETCLOSE},
    //
    {"\\",P_BACKSLASH},
    //precompiler operator
    {"#",P_PRECOMP},                    // pre-compiler
    {"$",P_DOLLAR},
// RAVEN BEGIN
    {"�",P_INVERTED_PLING},
    {"�",P_INVERTED_QUERY},
// RAVEN END
    {NULL, 0}
};

int default_punctuationtable[256];
int default_nextpunctuation[sizeof(default_punctuations) / sizeof(punctuation_t)];
int default_setup;

// RAVEN BEGIN
// jsinger: changed to be Lexer instead of idLexer so that we have the ability to read binary files
static NSString *baseFolder;

// Added this to allow easy changing of the suffix that signifies a binary file
//idStr const        Lexer::sCompiledFileSuffix("c");
// RAVEN END


@implementation idLexer

- (BOOL)isLoaded {
    return self->loaded;
}

- (const char*)buffer {
    return self->buffer;
}

- (const char*)scriptPointer {
    return self->script_p;
}

- (NSString *)fileName {
    return self->filename;
}

- (const int)fileOffset {
    return (int)(self->script_p - self->buffer);
}

- (const unsigned int)fileTime {
    return self->fileTime;
}

- (const int)lineNum {
    return line;
}

- (void)setFlags:(int)flags {
    self->flags = flags;
}

- (int)flags {
    return self->flags;
}

-(void)createPunctuationTable:(const punctuation_t *)punctuations {
    int i, n, lastp;
    const punctuation_t *p, *newp;

    //get memory for the table
    if (punctuations == default_punctuations) {
        self->punctuationtable = default_punctuationtable;
        self->nextpunctuation = default_nextpunctuation;
        if (default_setup) {
            return;
        }
        default_setup = YES;
        i = sizeof(default_punctuations) / sizeof(punctuation_t);
    } else {
        if (!self->punctuationtable || self->punctuationtable == default_punctuationtable) {
            self->punctuationtable = (int *)malloc(256 * sizeof(int));
        }
        if (self->nextpunctuation && self->nextpunctuation != default_nextpunctuation) {
            free(self->nextpunctuation);
        }
        for (i = 0; punctuations[i].p; i++) {
        }
        self->nextpunctuation = (int *)malloc(i * sizeof(int));
    }
    memset(self->punctuationtable, 0xFF, 256 * sizeof(int));
    memset(self->nextpunctuation, 0xFF, i * sizeof(int));
    //add the punctuations in the list to the punctuation table
    for (i = 0; punctuations[i].p; i++) {
        newp = &punctuations[i];
        const unsigned int tableIndex = (unsigned char)( newp->p[0] );
        lastp = -1;
        //sort the punctuations in this table entry on length (longer punctuations first)
        for (n = self->punctuationtable[tableIndex]; n >= 0; n = self->nextpunctuation[n] ) {
            p = &punctuations[n];
            if (strlen(p->p) < strlen(newp->p)) {
                self->nextpunctuation[i] = n;
                if (lastp >= 0) {
                    self->nextpunctuation[lastp] = i;
                }
                else {
                    self->punctuationtable[tableIndex] = i;
                }
                break;
            }
            lastp = n;
        }
        if (n < 0) {
            self->nextpunctuation[i] = -1;
            if (lastp >= 0) {
                self->nextpunctuation[lastp] = i;
            }
            else {
                self->punctuationtable[tableIndex] = i;
            }
        }
    }
}

-(const char *)punctuationFromId:(int)ident {
    int i;

    for (i = 0; self->punctuations[i].p; i++) {
        if (self->punctuations[i].n == ident) {
            return self->punctuations[i].p;
        }
    }
    return "unkown punctuation";
}

- (int)punctuationId:(const char *)p {
    int i;

    for (i = 0; self->punctuations[i].p; i++) {
        if ( !strcmp(self->punctuations[i].p, p) ) {
            return punctuations[i].n;
        }
    }
    return 0;
}

- (BOOL)error:(NSError **)error format:(NSString *)format, ... {
    va_list ap;

    self->hadError = YES;

    if ( self->flags & LEXFL_NOERRORS ) {
        return YES;
    }

    va_start(ap, format);
    NSString *result = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    
    if (self->flags & LEXFL_NOFATALERRORS) {
        NSLog(@"file %@, line %d: %@", self->filename, self->line, result);
        return YES;
    } else {
        if (error != NULL) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"file %@, line %d: %@", self->filename, self->line, result]
            };
            
            // Create the error and assign it to the dereferenced pointer
            *error = [NSError errorWithDomain:@"org.underivable.udquaketools.lexer"
                                         code:1001
                                     userInfo:userInfo];
        }
        return NO;
    }
}

- (void)warning:(NSString *)format, ... {
    va_list ap;

    if (self->flags & LEXFL_NOWARNINGS ) {
        return;
    }

    va_start(ap, format);
    NSString *result = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);

    NSLog(@"file %@, line %d: %@", self->filename, self->line, result);
}

- (void)setPunctuations:(const punctuation_t *)p {
#ifdef PUNCTABLE
    if (p) {
        [self createPunctuationTable:p];
    } else {
        [self createPunctuationTable:default_punctuations];
    }
#endif //PUNCTABLE
    if (p) {
        self->punctuations = p;
    } else {
        self->punctuations = default_punctuations;
    }
}

- (BOOL)readWhiteSpace:(NSError **)error {
    while (1) {
        // skip white space
// RAVEN BEGIN
        while ((unsigned char)*self->script_p <= ' ') {
// RAVEN END
            if (!*self->script_p) {
                return NO;
            }
            if (*self->script_p == '\n') {
                self->line++;
            }
            self->script_p++;
        }
        // skip comments
        if (*self->script_p == '/') {
            // comments //
            if (*(self->script_p+1) == '/') {
                self->script_p++;
                do {
                    self->script_p++;
                    if (!*self->script_p) {
                        [self error:error format:@"unexpected EOF while expecting comment"];
                        return NO;
                    }
                }
                while (*self->script_p != '\n');
                self->line++;
                self->script_p++;
                if (!*self->script_p) {
                    [self error:error format:@"unexpected EOF while expecting whitespace"];
                    return NO;
                }
                continue;
            }
            // comments /* */
            else if (*(self->script_p+1) == '*') {
                self->script_p++;
                while (1) {
                    self->script_p++;
                    if ( !*self->script_p ) {
                        [self error:error format:@"unexpected EOF while expecting end of block comment"];
                        return NO;
                    }
                    if ( *self->script_p == '\n' ) {
                        self->line++;
                    }
                    else if ( *self->script_p == '/' ) {
                        if ( *(self->script_p-1) == '*' ) {
                            break;
                        }
                        if ( *(self->script_p+1) == '*' ) {
                            [self warning:@"nested comment"];
                        }
                    }
                }
                self->script_p++;
                if (!*self->script_p) {
                    [self error:error format:@"unexpected EOF while expecting end of block comment"];
                    return NO;
                }
                self->script_p++;
                if (!*self->script_p) {
                    [self error:error format:@"unexpected EOF while expecting end of block comment"];
                    return NO;
                }
                continue;
            }
        }
        break;
    }
    return YES;
}

- (BOOL)readEscapeCharacter:(char *)ch error:(NSError **)error {
    int c, val, i;

    // step over the leading '\\'
    self->script_p++;
    // determine the escape character
    switch(*self->script_p) {
        case '\\': c = '\\'; break;
        case 'n': c = '\n'; break;
        case 'r': c = '\r'; break;
        case 't': c = '\t'; break;
        case 'v': c = '\v'; break;
        case 'b': c = '\b'; break;
        case 'f': c = '\f'; break;
        case 'a': c = '\a'; break;
        case '\'': c = '\''; break;
        case '\"': c = '\"'; break;
        case '\?': c = '\?'; break;
        case 'x':
        {
            self->script_p++;
            for (i = 0, val = 0; ; i++, self->script_p++) {
                c = *self->script_p;
                if (c >= '0' && c <= '9')
                    c = c - '0';
                else if (c >= 'A' && c <= 'Z')
                    c = c - 'A' + 10;
                else if (c >= 'a' && c <= 'z')
                    c = c - 'a' + 10;
                else
                    break;
                val = (val << 4) + c;
            }
            self->script_p--;
            if (val > 0xFF) {
                [self warning:@"too large value in escape character"];
                val = 0xFF;
            }
            c = val;
            break;
        }
        default: //NOTE: decimal ASCII code, NOT octal
        {
            if (*self->script_p < '0' || *self->script_p > '9') {
                if (![self error:error format:@"unknown escape char"]) {
                    return NO;
                }
            }
            for (i = 0, val = 0; ; i++, self->script_p++) {
                c = *self->script_p;
                if (c >= '0' && c <= '9')
                    c = c - '0';
                else
                    break;
                val = val * 10 + c;
            }
            self->script_p--;
            if (val > 0xFF) {
                [self warning:@"too large value in escape character"];
                val = 0xFF;
            }
            c = val;
            break;
        }
    }
    // step over the escape character or the last digit of the number
    self->script_p++;
    // store the escape character
    *ch = c;
    // succesfully read escape character
    return YES;
}

-(BOOL)readString:(idToken *)token quote:(int)quote error:(NSError **)error {
    int tmpline;
    const char *tmpscript_p;
    char ch;

    if ( quote == '\"' ) {
        token->type = TT_STRING;
    } else {
        token->type = TT_LITERAL;
    }

    // leading quote
    self->script_p++;

    while(1) {
        // if there is an escape character and escape characters are allowed
        if (*self->script_p == '\\' && !(self->flags & LEXFL_NOSTRINGESCAPECHARS)) {
            if (![self readEscapeCharacter:&ch error:error]) {
                return NO;
            }
            idToken_AppendDirty(token, ch);
        }
        // if a trailing quote
        else if (*self->script_p == quote) {
            // step over the quote
            self->script_p++;
            // if consecutive strings should not be concatenated
            if ( (self->flags & LEXFL_NOSTRINGCONCAT) &&
                    (!(self->flags & LEXFL_ALLOWBACKSLASHSTRINGCONCAT) || (quote != '\"')) ) {
                break;
            }

            tmpscript_p = self->script_p;
            tmpline = self->line;
            // read white space between possible two consecutive strings
            if (![self readWhiteSpace:error]) {
                self->script_p = tmpscript_p;
                self->line = tmpline;
                break;
            }

            if (self->flags & LEXFL_NOSTRINGCONCAT) {
                if (*self->script_p != '\\') {
                    self->script_p = tmpscript_p;
                    self->line = tmpline;
                    break;
                }
                // step over the '\\'
                self->script_p++;
                if (![self readWhiteSpace:error] || (*self->script_p != quote)) {
                    [self error:error format:@"expecting string after '\' terminated line"];
                    return NO;
                }
            }

            // if there's no leading qoute
            if (*self->script_p != quote) {
                self->script_p = tmpscript_p;
                self->line = tmpline;
                break;
            }
            // step over the new leading quote
            self->script_p++;
        } else {
            if (*self->script_p == '\0') {
                [self error:error format:@"missing trailing quote"];
                return NO;
            }
            if (*self->script_p == '\n') {
                [self error:error format:@"newline inside string"];
                return NO;
            }
            idToken_AppendDirty(token, *self->script_p++);
        }
    }
    idToken_ZeroTerminate(token);

    if (token->type == TT_LITERAL) {
        if (!(self->flags & LEXFL_ALLOWMULTICHARLITERALS)) {
            if (token->length != 1) {
                [self warning:@"literal is not one character long"];
            }
        }
        idToken_SetSubtypeFromFirstChar(token);
    }
    else {
        // the sub type is the length of the string
        idToken_SetSubtypeFromLength(token);
    }
    return YES;
}

- (BOOL)readName:(idToken *)token error:(NSError **)error {
    char c;

    token->type = TT_NAME;
    do {
        idToken_AppendDirty(token, *self->script_p++);
        c = *self->script_p;
// RAVEN BEGIN
    } while (isalpha(c) || isdigit(c) || c == '_' ||
// RAVEN EBD
                // if treating all tokens as strings, don't parse '-' as a seperate token
                ((self->flags & LEXFL_ONLYSTRINGS) && (c == '-')) ||
                // if special path name characters are allowed
                ((self->flags & LEXFL_ALLOWPATHNAMES) && (c == '/' || c == '\\' || c == ':' || c == '.')));
    idToken_ZeroTerminate(token);
    //the sub type is the length of the name
    idToken_SetSubtypeFromLength(token);
    return YES;
}

- (int)checkString:(const char *)str {
    int i;

    for ( i = 0; str[i]; i++ ) {
        if ( self->script_p[i] != str[i] ) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)readNumber:(idToken *)token error:(NSError **)error {
    int i;
    int dot;
    char c, c2;

    idToken_SetTypeNumber(token);

    c = *self->script_p;
    c2 = *(self->script_p + 1);

    if (c == '0' && c2 != '.') {
        // check for a hexadecimal number
        if (c2 == 'x' || c2 == 'X') {
            idToken_AppendDirty(token, *self->script_p++);
            idToken_AppendDirty(token, *self->script_p++);
            c = *self->script_p;
            while((c >= '0' && c <= '9') ||
                        (c >= 'a' && c <= 'f') ||
                        (c >= 'A' && c <= 'F')) {
                idToken_AppendDirty(token, c);
                c = *(++self->script_p);
            }
            token->subtype = TT_HEX | TT_INTEGER;
        }
        // check for a binary number
        else if (c2 == 'b' || c2 == 'B') {
            idToken_AppendDirty(token, *self->script_p++);
            idToken_AppendDirty(token, *self->script_p++);
            c = *self->script_p;
            while (c == '0' || c == '1') {
                idToken_AppendDirty(token, c);
                c = *(++self->script_p);
            }
            token->subtype = TT_BINARY | TT_INTEGER;
        }
        // its an octal number
        else {
            idToken_AppendDirty(token, *self->script_p++);
            c = *self->script_p;
            while (c >= '0' && c <= '7') {
                idToken_AppendDirty(token, c);
                c = *(++self->script_p);
            }
            token->subtype = TT_OCTAL | TT_INTEGER;
        }
    } else {
        // decimal integer or floating point number or ip address
        dot = 0;
        while (1) {
            if (c >= '0' && c <= '9') {
            }
            else if (c == '.') {
                dot++;
            } else {
                break;
            }
            idToken_AppendDirty(token, c);
            c = *(++self->script_p);
        }
        if (c == 'e' && dot == 0) {
            //We have scientific notation without a decimal point
            dot++;
        }
        // if a floating point number
        if (dot == 1) {
            token->subtype = TT_DECIMAL | TT_FLOAT;
            // check for floating point exponent
            if (c == 'e') {
                //Append the e so that GetFloatValue code works
                idToken_AppendDirty(token, c);
                c = *(++self->script_p);
                if (c == '-') {
                    idToken_AppendDirty(token, c);
                    c = *(++self->script_p);
                }
                else if (c == '+') {
                    idToken_AppendDirty(token, c);
                    c = *(++self->script_p);
                }
                while (c >= '0' && c <= '9') {
                    idToken_AppendDirty(token, c);
                    c = *(++self->script_p);
                }
            }
            // check for floating point exception infinite 1.#INF or indefinite 1.#IND or NaN
            else if (c == '#') {
                c2 = 4;
                if ([self checkString:"INF"]) {
                    token->subtype |= TT_INFINITE;
                }
                else if ([self checkString:"IND"]) {
                    token->subtype |=  TT_INDEFINITE;
                }
                else if ([self checkString:"NAN"]) {
                    token->subtype |= TT_NAN;
                }
                else if ([self checkString:"QNAN"]) {
                    token->subtype |= TT_NAN;
                    c2++;
                }
                else if ([self checkString:"SNAN"]) {
                    token->subtype |= TT_NAN;
                    c2++;
                }
                for (i = 0; i < c2; i++) {
                    idToken_AppendDirty(token, c);
                    c = *(++self->script_p);
                }
                while (c >= '0' && c <= '9') {
                    idToken_AppendDirty(token, c);
                    c = *(++self->script_p);
                }
                if (!(self->flags & LEXFL_ALLOWFLOATEXCEPTIONS)) {
                    idToken_ZeroTerminate(token);    // zero terminate for c_str
                    if (![self error:error format:@"parsed %s", token->text]) {
                        return NO;
                    }
                }
            }
        }
        else if (dot > 1) {
            if (!(self->flags & LEXFL_ALLOWIPADDRESSES)) {
                [self error:error format:@"more than one dot in number"];
                return NO;
            }
            if (dot != 3) {
                [self error:error format:@"ip address should have three dots"];
                return NO;
            }
            token->subtype = TT_IPADDRESS;
        }
        else {
            token->subtype = TT_DECIMAL | TT_INTEGER;
        }
    }

    if (token->subtype & TT_FLOAT) {
        if ( c > ' ' ) {
            // single-precision: float
            if ( c == 'f' || c == 'F' ) {
                token->subtype |= TT_SINGLE_PRECISION;
                self->script_p++;
            }
            // extended-precision: long double
            else if (c == 'l' || c == 'L') {
                token->subtype |= TT_EXTENDED_PRECISION;
                self->script_p++;
            }
            // default is double-precision: double
            else {
                token->subtype |= TT_DOUBLE_PRECISION;
            }
        } else {
            token->subtype |= TT_DOUBLE_PRECISION;
        }
    } else if (token->subtype & TT_INTEGER) {
        if (c > ' ') {
            // default: signed long
            for (i = 0; i < 2; i++) {
                // long integer
                if (c == 'l' || c == 'L') {
                    token->subtype |= TT_LONG;
                }
                // unsigned integer
                else if (c == 'u' || c == 'U') {
                    token->subtype |= TT_UNSIGNED;
                } else {
                    break;
                }
                c = *(++self->script_p);
            }
        }
    } else if (token->subtype & TT_IPADDRESS) {
        if (c == ':') {
            idToken_AppendDirty(token, c);
            c = *(++self->script_p);
            while (c >= '0' && c <= '9') {
                idToken_AppendDirty(token, c);
                c = *(++self->script_p);
            }
            token->subtype |= TT_IPPORT;
        }
    }
    idToken_ZeroTerminate(token);
    return YES;
}

- (BOOL)readPunctuation:(idToken *)token error:(NSError **)error {
    int l, n;
    const char *p;
    const punctuation_t *punc;

#ifdef PUNCTABLE
    for (n = self->punctuationtable[(unsigned char)( *(self->script_p) )]; n >= 0; n = self->nextpunctuation[n]) {
        punc = &(self->punctuations[n]);
#else
    int i;

    for (i = 0; self->punctuations[i].p; i++) {
        punc = &self->punctuations[i];
#endif
        p = punc->p;
        // check for this punctuation in the script
        for ( l = 0; p[l] && self->script_p[l]; l++ ) {
            if ( self->script_p[l] != p[l] ) {
                break;
            }
        }
        if ( !p[l] ) {
            idToken_CopyFromBuffer(token, p, l);
            self->script_p += l;
            token->type = TT_PUNCTUATION;
            // sub type is the punctuation id
            token->subtype = punc->n;
            return YES;
        }
    }
    return NO;
}

- (BOOL)readToken:(idToken *)token error:(NSError **)error {
    int c;

    if (!self->loaded) {
// RAVEN BEGIN
        [self error:error format:@"readToken: no file loaded"];
// RAVEN END
        return NO;
    }

    // if there is a token available (from unreadToken)
    if (self->tokenavailable) {
        self->tokenavailable = 0;
        idToken_AssignFromToken(token, &self->token);
        return YES;
    }
    // save script pointer
    self->lastScript_p = self->script_p;
    // save line counter
    self->lastline = self->line;
    // clear the token stuff
    idToken_Clear(token);
    // start of the white space
    self->whiteSpaceStart_p = self->script_p;
    token->whiteSpaceStart_p = self->script_p;
    // read white space before token
    if (![self readWhiteSpace:error]) {
        return NO;
    }
    // end of the white space
    self->whiteSpaceEnd_p = self->script_p;
    token->whiteSpaceEnd_p = self->script_p;
    // line the token is on
    token->line = self->line;
    // number of lines crossed before token
    token->linesCrossed = self->line - self->lastline;
    // clear token flags
    token->flags = 0;

    c = *self->script_p;

    // if we're keeping everything as whitespace deliminated strings
    if (self->flags & LEXFL_ONLYSTRINGS) {
        // if there is a leading quote
        if (c == '\"' || c == '\'') {
            if (![self readString:token quote:c error:error]) {
                return NO;
            }
        } else if (![self readName:token error:error]) {
            return NO;
        }
    }
    // if there is a number
    else if ((c >= '0' && c <= '9') ||
            (c == '.' && (*(self->script_p + 1) >= '0' && *(self->script_p + 1) <= '9')) ) {
        if (![self readNumber:token error:error]) {
            return NO;
        }
        // if names are allowed to start with a number
        if (self->flags & LEXFL_ALLOWNUMBERNAMES) {
            c = *self->script_p;
            if (isalpha(c) || isdigit(c) || c == '_') {
                if (![self readName:token error:error]) {
                    return NO;
                }
            }
        }
    }
    // if there is a leading quote
    else if (c == '\"' || c == '\'') {
        if (![self readString:token quote:c error:error]) {
            return NO;
        }
    }
    // if there is a name
// RAVEN BEGIN
    else if (isalpha(c) || isdigit(c) || c == '_') {
// RAVEN END
        if (![self readName:token error:error]) {
            return NO;
        }
    }
    // names may also start with a slash when pathnames are allowed
    else if ((self->flags & LEXFL_ALLOWPATHNAMES) && ((c == '/' || c == '\\') || c == '.')) {
        if (![self readName:token error:error]) {
            return NO;
        }
    }
    // check for punctuations
    else if (![self readPunctuation:token error:error]) {
        [self error:error format:@"unknown punctuation %C", c];
        return NO;
    }

    // succesfully read a token
    return YES;
}

- (BOOL)expectTokenString:(NSString *)string error:(NSError **)error {
    idToken token;
    
    idToken_Init(&token);

    if (![self readToken:&token error:error]) {
        [self error:error format:@"couldn't find expected '%@'", string];
        return NO;
    }
    if (strcmp(token.text, [string UTF8String])) {
        [self error:error format:@"expected '%@' but found '%s'", string, token.text];
        return NO;
    }
    return YES;
}

- (BOOL)expectTokenType:(int)type subtype:(int)subtype into:(idToken *)token error:(NSError **)error {
    NSString *str;

    if (![self readToken:token error:error]) {
        [self error:error format:@"couldn't read expected token"];
        return NO;
    }

    if (token->type != type) {
        switch(type) {
            case TT_STRING: str = @"string"; break;
            case TT_LITERAL: str = @"literal"; break;
            case TT_NUMBER: str = @"number"; break;
            case TT_NAME: str = @"name"; break;
            case TT_PUNCTUATION: str = @"punctuation"; break;
            default: str = @"unknown type"; break;
        }
        [self error:error format:@"expected a %@ but found '%s'", str, token->text];
        return NO;
    }
    if (token->type == TT_NUMBER) {
        if ((token->subtype & subtype) != subtype ) {
            str = @"";
            if (subtype & TT_DECIMAL) str = @"decimal ";
            if (subtype & TT_HEX) str = @"hex ";
            if (subtype & TT_OCTAL) str = @"octal ";
            if (subtype & TT_BINARY) str = @"binary ";
            if (subtype & TT_UNSIGNED) str = [str stringByAppendingString:@"unsigned "];
            if (subtype & TT_LONG) str = [str stringByAppendingString:@"long "];
            if (subtype & TT_FLOAT) str = [str stringByAppendingString:@"float "];
            if (subtype & TT_INTEGER) str = [str stringByAppendingString:@"integer "];
            str = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [self error:error format:@"expected %@ but found '%s'", str, token->text];
            return NO;
        }
    }
    else if (token->type == TT_PUNCTUATION) {
        if (subtype < 0) {
            [self error:error format:@"BUG: wrong punctuation subtype"];
            return NO;
        }
        if (token->subtype != subtype ) {
            [self error:error format:@"expected '%@' but found '%s'", [self punctuationFromId:subtype], token->text];
            return NO;
        }
    }
    return YES;
}

-(BOOL)expectAnyToken:(idToken *)token error:(NSError **)error {
    if (![self readToken:token error:error]) {
        [self error:error format:@"couldn't read expected token"];
        return NO;
    } else {
        return YES;
    }
}

-(BOOL)checkTokenString:(NSString *)string error:(NSError **)error {
    idToken tok;
    
    idToken_Init(&tok);

    if (![self readToken:&tok error:error]) {
        return NO;
    }

    // if the token is available
    if (!strcmp(tok.text, [string UTF8String])) {
        return YES;
    }
    // token not available
    [self unreadToken:&tok error:error];
    return NO;
}

-(BOOL)checkTokenType:(int)type subtype:(int)subtype into:(idToken *)token error:(NSError **)error {
    idToken tok;

    idToken_Init(&tok);
    if (![self readToken:&tok error:error]) {
        return NO;
    }
    // if the type matches
    if (tok.type == type && (tok.subtype & subtype) == subtype) {
        idToken_AssignFromToken(token, &tok);
        return YES;
    }
    // token is not available
    self->script_p = self->lastScript_p;
    self->line = self->lastline;
    return NO;
}

-(BOOL)skipUntilString:(NSString *)string error:(NSError **)error {
    idToken token;
    
    idToken_Init(&token);
    while ([self readToken:&token error:error]) {
        if (!strcmp(token.text, [string UTF8String])) {
            return YES;
        }
    }
    return NO;
}

-(BOOL)skipRestOfLine:(NSError **)error {
    idToken token;

    idToken_Init(&token);
    while ([self readToken:&token error:error]) {
        if (token.linesCrossed) {
            self->script_p = self->lastScript_p;
            self->line = self->lastline;
            return YES;
        }
    }
    return NO;
}

-(BOOL)skipBracedSection:(BOOL)parseFirstBrace error:(NSError **)error {
    idToken token;
    int depth;

    idToken_Init(&token);
    depth = parseFirstBrace ? 0 : 1;
    do {
        if (![self readToken:&token error:error]) {
            return NO;
        }
        if (token.type == TT_PUNCTUATION ) {
            if (token.text[0] == '{') {
                depth++;
            } else if (token.text[0] == '}') {
                depth--;
            }
        }
    } while(depth);
    return YES;
}

-(BOOL)unreadToken:(idToken *)token error:(NSError **)error {
    if (self->tokenavailable) {
        [self error:error format:@"unreadToken, unread token twice"];
        return NO;
    }
    idToken_AssignFromToken(&self->token, token);
    self->tokenavailable = 1;
    return YES;
}

-(BOOL)readTokenOnLine:(idToken *)token error:(NSError **)error {
    idToken tok;

    idToken_Init(&tok);
    if (![self readToken:&tok error:error]) {
        self->script_p = self->lastScript_p;
        self->line = self->lastline;
        return NO;
    }
    // if no lines were crossed before this token
    if (!tok.linesCrossed) {
        idToken_AssignFromToken(token, &tok);
        return YES;
    }
    // restore our position
    self->script_p = self->lastScript_p;
    self->line = self->lastline;
    idToken_Clear(token);
    return NO;
}

-(void)readRestOfLine:(NSMutableString *)str {
    while(1) {

        if (*self->script_p == '\n') {
            self->line++;
            break;
        }

        if(!*self->script_p) {
            break;
        }

        if(*self->script_p <= ' ') {
            [str appendString:@" "];
        } else {
            [str appendFormat:@"%C", *self->script_p];
        }
        self->script_p++;

    }

    CFStringTrimWhitespace((__bridge CFMutableStringRef)str);
}

-(BOOL)parseInt:(int *)result error:(NSError **)error {
    idToken token;
    
    idToken_Init(&token);

    if (![self readToken:&token error:error]) {
        [self error:error format:@"couldn't read expected integer"];
        return NO;
    }
    if (token.type == TT_PUNCTUATION && token.text[0] == '-') {
        if (![self expectTokenType:TT_NUMBER subtype:TT_INTEGER into:&token error:error]) {
            return NO;
        }
        if (result) {
            *result = -((signed int)idToken_IntValue(&token));
        }
        return YES;
    } else if (token.type != TT_NUMBER || token.subtype == TT_FLOAT) {
        [self error:error format:@"expected integer value, found '%s'", token.text];
        return NO;
    }
    if (result) {
        *result = idToken_IntValue(&token);
    }
    return YES;
}

-(BOOL)parseBool:(BOOL *)result error:(NSError **)error {
    idToken token;

    idToken_Init(&token);
    if ( ![self expectTokenType:TT_NUMBER subtype:0 into:&token error:error]) {
        [self error:error format:@"couldn't read expected boolean"];
        return NO;
    }
    if (result) {
        *result = (idToken_IntValue(&token) != 0);
    }
    return YES;
}

-(BOOL)parseFloat:(float *)result error:(NSError **)error {
    idToken token;

    idToken_Init(&token);
    if (![self readToken:&token error:error]) {
        return NO;
    }
    if (token.type == TT_PUNCTUATION && token.text[0] == '-') {
        if (![self expectTokenType:TT_NUMBER subtype:0 into:&token error:error]) {
            return NO;
        }
        if (result) {
            *result = -idToken_FloatValue(&token);
        }
        return YES;
    } else if (token.type != TT_NUMBER) {
        [self error:error format:@"expected float value, found '%s'", token.text];
        return NO;
    }
    if (result) {
        *result = idToken_FloatValue(&token);
    }
    return YES;
}

-(BOOL)parse1DMatrix:(int)x matrix:(float *)m error:(NSError **)error {
    int i;

    if (![self expectTokenString:@"(" error:error]) {
        return NO;
    }

    for (i = 0; i < x; i++) {
        if (![self parseFloat:&m[i] error:error]) {
            return NO;
        }
    }

    if (![self expectTokenString:@")" error:error]) {
        return NO;
    }
    return YES;
}

// RAVEN BEGIN
// rjohnson: added vertex color support to proc files.  assume a default RGBA of 0x000000ff
-(BOOL)parse1DMatrixOpenEnded:(int)maxCount parsedCount:(int *)parsedCount matrix:(float *)m error:(NSError *__autoreleasing *)error {
    int i;

    if (![self expectTokenString:@"(" error:error]) {
        return NO;
    }

    idToken tok;
    
    idToken_Init(&tok);

    for (i = 0; i < maxCount; i++) {
        if (![self readToken:&tok error:error]) {
            return NO;
        }

        if (!strcmp(tok.text, ")")) {
            if (parsedCount) *parsedCount = i;
            return YES;
        }

        if (![self unreadToken:&tok error:error]) {
            return NO;
        }

        if (![self parseFloat:&m[i] error:error]) {
            return NO;
        }
    }

    if (![self expectTokenString:@")" error:error]) {
        return NO;
    }

    if (parsedCount) *parsedCount = i;
    return YES;
}
// RAVEN END

-(BOOL)parse2DMatrix:(int)y x:(int)x matrix:(float *)m error:(NSError **)error {
    int i;

    if (![self expectTokenString:@"(" error:error]) {
        return NO;
    }

    for (i = 0; i < y; i++) {
        if (![self parse1DMatrix:x matrix:m + i * x error:error]) {
            return NO;
        }
    }

    if (![self expectTokenString:@")" error:error]) {
        return NO;
    }
    return YES;
}

-(BOOL)parse3DMatrix:(int)z y:(int)y x:(int)x matrix:(float *)m error:(NSError **)error {
    int i;

    if (![self expectTokenString:@"(" error:error]) {
        return NO;
    }

    for (i = 0 ; i < z; i++) {
        if (![self parse2DMatrix:y x:x matrix:m + i * x*y error:error]) {
            return NO;
        }
    }

    if (![self expectTokenString:@")" error:error]) {
        return NO;
    }
    return YES;
}

/*
-(void)parseNumericStructArray( int numStructElements, int tokenSubTypeStructElements[], int arrayCount, byte *arrayStorage )
{
    int arrayOffset, curElement;

    for ( arrayOffset = 0; arrayOffset < arrayCount; arrayOffset++ )
    {
        for ( curElement = 0; curElement < numStructElements; curElement++ )
        {
            if ( tokenSubTypeStructElements[curElement] & TT_FLOAT )
            {
                *(float*)arrayStorage = idLexer::ParseFloat();
                arrayStorage += sizeof(float);
            }
            else
            {
                *(int*)arrayStorage = idLexer::ParseInt();
                arrayStorage += sizeof(int);
            }
        }
    }
}*/

-(BOOL)parseBracedSectionExact:(NSMutableString *)str tabs:(int)tabs error:(NSError **)error {
    int     depth;
    BOOL    doTabs;
    BOOL    skipWhite;

    [str setString:@""];

    if (![self expectTokenString:@"{" error:error]) {
        return NO;
    }

    [str setString:@"{"];
    depth = 1;
    skipWhite = NO;
    doTabs = tabs >= 0;

    while (depth && *self->script_p) {
        char c = *self->script_p++;

        switch (c) {
            case '\t':
            case ' ': {
                if (skipWhite) {
                    continue;
                }
                break;
            }
            case '\n': {
// RAVEN BEGIN
// jscott: now gives correct line number in error reports
                line++;
// RAVEN END
                if (doTabs) {
                    skipWhite = YES;
                    [str appendFormat:@"%C", c];
                    continue;
                }
                break;
            }
            case '{': {
                depth++;
                tabs++;
                break;
            }
            case '}': {
                depth--;
                tabs--;
                break;
            }
        }

        if (skipWhite) {
            int i = tabs;
            if (c == '{') {
                i--;
            }
            skipWhite = NO;
            for ( ; i > 0; i-- ) {
                [str appendString:@"\t"];
            }
        }
        [str appendFormat:@"%C", c];
    }
    
    return YES;
}

-(BOOL)parseBracedSection:(NSMutableString *)str error:(NSError **)error {
    idToken token;
    int i, depth;
    
    idToken_Init(&token);
    [str setString:@""];
    if (![self expectTokenString:@"{" error:error]) {
        return NO;
    }
    [str setString:@"{"];
    depth = 1;
    do {
        if (![self readToken:&token error:error]) {
            [self error:error format:@"missing closing brace"];
            return NO;
        }

        // if the token is on a new line
        for (i = 0; i < token.linesCrossed; i++ ) {
            [str appendString:@"\r\n"];
        }

        if (token.type == TT_PUNCTUATION ) {
            if (token.text[0] == '{') {
                depth++;
            } else if (token.text[0] == '}') {
                depth--;
            }
        }

        if (token.type == TT_STRING) {
            [str appendFormat:@"\"%s\"", token.text];
        } else {
            [str appendFormat:@"%s", token.text];
        }
        [str appendString:@" "];
    } while (depth);
    return YES;
}

-(BOOL)parseRestOfLine:(NSMutableString *)str error:(NSError **)error {
    idToken token;

    idToken_Init(&token);
    [str setString:@""];
    while (1) {
        if (![self readToken:&token error:error]) {
            return NO;
        }
        if (token.linesCrossed) {
            self->script_p = self->lastScript_p;
            self->line = self->lastline;
            break;
        }
        if ([str length]) {
            [str appendString:@" "];
        }
        [str appendFormat:@"%s", token.text];
    }
    return YES;
}

-(int)lastWhiteSpace:(NSMutableString*)whiteSpace {
    [whiteSpace setString:@""];
    for (const char *p = self->whiteSpaceStart_p; p < self->whiteSpaceEnd_p; p++ ) {
        [whiteSpace appendFormat:@"%C", *p];
    }
    return (int)[whiteSpace length];
}

-(int)lastWhiteSpaceStart {
    return (int)(self->whiteSpaceStart_p - self->buffer);
}

-(int)lastWhiteSpaceEnd {
    return (int)(self->whiteSpaceEnd_p - self->buffer);
}

-(void)reset {
    // pointer in script buffer
    self->script_p = self->buffer;
    // pointer in script buffer before reading token
    self->lastScript_p = self->buffer;
    // begin of white space
    self->whiteSpaceStart_p = NULL;
    // end of white space
    self->whiteSpaceEnd_p = NULL;
    // set if there's a token available in idLexer::token
    self->tokenavailable = 0;

    self->line = 1;
    self->lastline = 1;
    // clear the saved token
    idToken_Clear(&self->token);
}

-(int)endOfFile {
    return self->script_p >= self->end_p;
}

-(int)numLinesCrossed {
    return self->line - self->lastline;
}

-(BOOL)loadFile:(NSString *)filename isOSPath:(bool)OSPath error:(NSError **)error {
    idFile *fp;
    NSString *pathname;
    int length;
    char *buf;

    if (self->loaded) {
        [self error:error format:@"loadFile: another script already loaded"];
        return NO;
    }
    
    if (!OSPath && [baseFolder length] != 0) {
        pathname = [NSString stringWithFormat:@"%@/%@", baseFolder, filename];
    } else {
        pathname = filename;
    }
    if ( OSPath ) {
        fp = [self.fileSystem openExplicitFileRead:pathname];
    } else {
        fp = [self.fileSystem openFileRead:pathname allowCopyFiles:YES gamedir:nil error:error];
    }
    if (!fp) {
        return NO;
    }
    length = [fp length];
// RAVEN BEGIN
// amccarthy: Added memory allocation tag
    buf = (char *)malloc( length + 1);
    if (!buf) {
        [self error:error format:@"Memory system failure : out of memory"];
        return NO;
    }
// RAVEN END
    buf[length] = '\0';
    [fp read:buf length:length error:error];
    self->fileTime = [fp timestamp];
    self->filename = [fp fullPath];
    if (![self.fileSystem closeFile:fp error:error]) {
        return NO;
    }

    self->buffer = buf;
    self->length = length;
    // pointer in script buffer
    self->script_p = self->buffer;
    // pointer in script buffer before reading token
    self->lastScript_p = self->buffer;
    // pointer to end of script buffer
    self->end_p = &(self->buffer[length]);

    self->tokenavailable = 0;
    idToken_Init(&self->token);
    self->line = 1;
    self->lastline = 1;
    self->allocated = YES;
    self->loaded = YES;

    return YES;
}

-(BOOL)loadMemory:(const char *)ptr length:(int)length name:(NSString *)name startLine:(int)startLine error:(NSError **)error {
    if (self->loaded) {
        [self error:error format:@"loadMemory: another script already loaded"];
        return NO;
    }
    self->filename = name;
    self->buffer = ptr;
    self->fileTime = 0;
    self->length = length;
    // pointer in script buffer
    self->script_p = self->buffer;
    // pointer in script buffer before reading token
    self->lastScript_p = self->buffer;
    // pointer to end of script buffer
    self->end_p = &(self->buffer[length]);

    self->tokenavailable = 0;
    idToken_Init(&self->token);
    self->line = startLine;
    self->lastline = startLine;
    self->allocated = NO;
    self->loaded = YES;

    return YES;
}

-(void)freeSource {
#ifdef PUNCTABLE
    if (self->punctuationtable && self->punctuationtable != default_punctuationtable ) {
        free((void *)self->punctuationtable);
        self->punctuationtable = NULL;
    }
    if (self->nextpunctuation && self->nextpunctuation != default_nextpunctuation ) {
        free((void *)self->nextpunctuation);
        self->nextpunctuation = NULL;
    }
#endif //PUNCTABLE
    if (self->allocated) {
        free((void *)self->buffer);
        self->buffer = NULL;
        self->allocated = NO;
    }
    self->tokenavailable = 0;
    idToken_Init(&self->token);
    self->loaded = NO;
}

-(instancetype)initWithFileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->loaded = NO;
        self->filename = @"";
        self->flags = 0;
        [self setPunctuations:NULL];
        self->allocated = NO;
        self->fileTime = 0;
        self->length = 0;
        self->line = 0;
        self->lastline = 0;
        self->tokenavailable = 0;
        idToken_Init(&self->token);
        self->next = NULL;
        self->hadError = NO;
        self.fileSystem = fileSystem;
    }
    return self;
}

-(instancetype)initWithFlags:(int)flags fileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->loaded = NO;
        self->filename = @"";
        self->flags = flags;
        [self setPunctuations:NULL];
        self->allocated = NO;
        self->fileTime = 0;
        self->length = 0;
        self->line = 0;
        self->lastline = 0;
        self->tokenavailable = 0;
        idToken_Init(&self->token);
        self->next = NULL;
        self->hadError = NO;
        self.fileSystem = fileSystem;
    }
    return self;
}

- (instancetype)initWithFileName:(NSString *)filename
                           flags:(int)flags
                        isOSPath:(BOOL)isOSPath
                      fileSystem:(idFileSystem *)fileSystem
                           error:(NSError **)error {
    self = [super init];
    if (self)
    {
        self->loaded = NO;
        self->flags = flags;
        [self setPunctuations:NULL];
        self->allocated = NO;
        idToken_Init(&self->token);
        self->next = NULL;
        self->hadError = NO;
        self.fileSystem = fileSystem;
        [self loadFile:filename isOSPath:isOSPath error:error];
    }
    return self;
}

- (instancetype)initWithBuffer:(const char *)ptr
                        length:(int)length
                          name:(NSString *)name
                         flags:(int)flags
                    fileSystem:(idFileSystem *)fileSystem
                         error:(NSError **)error {
    self = [super init];
    if (self)
    {
        self->loaded = NO;
        self->flags = flags;
        [self setPunctuations:NULL];
        self->allocated = NO;
        idToken_Init(&self->token);
        self->next = NULL;
        self->hadError = NO;
        self.fileSystem = fileSystem;
        if (![self loadMemory:ptr length:length name:name startLine:1 error:error]) {
            return nil;
        }
    }
    return self;
}

-(void)dealloc {
    [self freeSource];
}

// RAVEN BEGIN
// jsinger: SetBaseFolder was moved to the Lexer base class to unify its functionality across all
//            derived classes
+ (void)setBaseFolder:(NSString *)path {
    baseFolder = [path copy];
}

// RAVEN END

-(BOOL)hadError {
    return self->hadError;
}

-(BOOL)peekTokenString:(NSString *)string error:(NSError **)error {
    idToken tok;

    idToken_Init(&tok);
    if (![self readToken:&tok error:error]) {
        return NO;
    }

    // unread token
    self->script_p = self->lastScript_p;
    self->line = self->lastline;

    // if the given string is available
    if (!strcmp(tok.text, [string UTF8String])) {
        return YES;
    }
    return NO;
}
    
-(idLexer *)next {
    return self->next;
}

-(void)setNext:(idLexer *)lexer {
    self->next = lexer;
}

@end

@implementation NSMutableData (CString)
- (void)appendUTF8StringAndNullTerminate:(const char *)string {
    if (!string || string[0] == '\0') return;
    
    // Strip old terminator
    if (self.length > 0) {
        self.length -= 1;
    }
    
    // Append new text
    [self appendBytes:string length:strlen(string)];
    
    // Add new terminator
    uint8_t nullByte = 0x00;
    [self appendBytes:&nullByte length:1];
}
@end
