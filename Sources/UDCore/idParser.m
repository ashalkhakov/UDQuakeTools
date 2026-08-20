#import "idParser.h"
#import "idFile.h"
#import "idFileSystem.h"

@interface NSMutableString (idStr)

- (void)stripTrailingChar:(unichar)c;
- (void)stripTrailingString:(NSString *)string;
- (void)backSlashesToSlashes;

@end
@implementation NSMutableString (idStr)

- (void)stripTrailingChar:(unichar)c {
    // Convert the single C-char to an NSString so Cocoa can compare it
    NSString *suffix = [NSString stringWithFormat:@"%C", c];
    
    // Loop backwards deleting the end character as long as it matches
    while (self.length > 0 && [self hasSuffix:suffix]) {
        [self deleteCharactersInRange:NSMakeRange(self.length - 1, 1)];
    }
}

- (void)stripTrailingString:(NSString *)string {
    NSUInteger l = string.length;
    
    // Safety check matching the C++ "if ( l > 0 )"
    if (l == 0) {
        return;
    }
    
    // Keep chopping off the end of the string as long as the suffix matches
    while (self.length >= l && [self hasSuffix:string]) {
        NSRange rangeToDelete = NSMakeRange(self.length - l, l);
        [self deleteCharactersInRange:rangeToDelete];
    }
}

- (void)backSlashesToSlashes {
    [self replaceOccurrencesOfString:@"\\" withString:@"/" options:NSLiteralSearch range:NSMakeRange(0, [self length])];
}

@end

static define_t *globaldefines;                // list with global defines added to every source loaded

//#define DEBUG_EVAL
#define MAX_DEFINEPARMS                128
#define DEFINEHASHSIZE                2048

#define TOKEN_FL_RECURSIVE_DEFINE    1

@implementation idParser

/*
ID_INLINE const char *idParser::GetFileName( void ) const {
    if ( idParser::scriptstack ) {
        return idParser::scriptstack->GetFileName();
    }
    else {
        return "";
    }
}

ID_INLINE const int idParser::GetFileOffset( void ) const {
    if ( idParser::scriptstack ) {
        return idParser::scriptstack->GetFileOffset();
    }
    else {
        return 0;
    }
}

ID_INLINE const unsigned int idParser::GetFileTime( void ) const {
    if ( idParser::scriptstack ) {
        return idParser::scriptstack->GetFileTime();
    }
    else {
        return 0;
    }
}

ID_INLINE const int idParser::GetLineNum( void ) const {
    if ( idParser::scriptstack ) {
        return idParser::scriptstack->GetLineNum();
    }
    else {
        return 0;
    }
}
*/

+(void)setBaseFolder:(NSString *)path {
// RAVEN BEGIN
// jsinger: changed to be Lexer instead of idLexer so that we have the ability to read binary files
    [idLexer setBaseFolder:path];
// RAVEN END
}

+(BOOL)addGlobalDefine:(NSString *)str {
    define_t *define;

    define = defineFromString([str UTF8String]);
    if (!define) {
        return NO;
    }
    define->next = globaldefines;
    globaldefines = define;
    return YES;
}

+(BOOL)removeGlobalDefine:(NSString *)name {
    define_t *d, *prev;

    for (prev = NULL, d = globaldefines; d; prev = d, d = d->next) {
        if (!strcmp(d->name, [name UTF8String])) {
            break;
        }
    }
    if (d) {
        if (prev) {
            prev->next = d->next;
        } else {
            globaldefines = d->next;
        }
        freeDefine(d);
        return YES;
    }
    return NO;
}

+(void)removeAllGlobalDefines {
    define_t *define;

    for (define = globaldefines; define; define = globaldefines) {
        globaldefines = globaldefines->next;
        freeDefine(define);
    }
}

/*
===============================================================================

idParser

===============================================================================
*/

/*
================
printDefine
================
*/
void printDefine( define_t *define ) {
    /*
    idLib::common->Printf("define->name = %s\n", define->name);
    idLib::common->Printf("define->flags = %d\n", define->flags);
    idLib::common->Printf("define->builtin = %d\n", define->builtin);
    idLib::common->Printf("define->numparms = %d\n", define->numparms);
    */
}

/*
================
PC_PrintDefineHashTable
================
* /
static void PC_PrintDefineHashTable(define_t **definehash) {
    int i;
    define_t *d;

    for (i = 0; i < DEFINEHASHSIZE; i++) {
        Log_Write("%4d:", i);
        for (d = definehash[i]; d; d = d->hashnext) {
            Log_Write(" %s", d->name);
        }
        Log_Write("\n");
    }
}
*/

static int PC_NameHash(const char *name) {
    int hash, i;

    hash = 0;
    for ( i = 0; name[i] != '\0'; i++ ) {
        hash += name[i] * (119 + i);
    }
    hash = (hash ^ (hash >> 10) ^ (hash >> 20)) & (DEFINEHASHSIZE-1);
    return hash;
}

static void addDefineToHash(define_t *define, define_t **definehash) {
    int hash;

    hash = PC_NameHash(define->name);
    define->hashnext = definehash[hash];
    definehash[hash] = define;
}

static define_t *findHashedDefine(define_t **definehash, const char *name) {
    define_t *d;
    int hash;

    hash = PC_NameHash(name);
    for ( d = definehash[hash]; d; d = d->hashnext ) {
        if ( !strcmp(d->name, name) ) {
            return d;
        }
    }
    return NULL;
}

static define_t *findDefine(define_t *defines, const char *name) {
    define_t *d;

    for ( d = defines; d; d = d->next ) {
        if ( !strcmp(d->name, name) ) {
            return d;
        }
    }
    return NULL;
}

static int findDefineParm(define_t *define, const char *name) {
    idToken *p;
    int i;

    i = 0;
    for ( p = define->parms; p; p = p->next) {
        if (!strcmp(p->text, name)) {
            return i;
        }
        i++;
    }
    return -1;
}

static define_t *copyDefine(define_t *define) {
    define_t *newdefine;
    idToken *token, *newtoken, *lasttoken;
//RAVEN BEGIN
//amccarthy: Added memory allocation tag
    newdefine = (define_t *)malloc(sizeof(define_t) + strlen(define->name) + 1);
//RAVEN END
    //copy the define name
    newdefine->name = (char *) newdefine + sizeof(define_t);
    strcpy(newdefine->name, define->name);
    newdefine->flags = define->flags;
    newdefine->builtin = define->builtin;
    newdefine->numparms = define->numparms;
    //the define is not linked
    newdefine->next = NULL;
    newdefine->hashnext = NULL;
    //copy the define tokens
    newdefine->tokens = NULL;
    for (lasttoken = NULL, token = define->tokens; token; token = token->next) {
        newtoken = malloc(sizeof(idToken));
        idToken_InitWithToken(newtoken, token);
        newtoken->next = NULL;
        if (lasttoken) lasttoken->next = newtoken;
        else newdefine->tokens = newtoken;
        lasttoken = newtoken;
    }
    //copy the define parameters
    newdefine->parms = NULL;
    for (lasttoken = NULL, token = define->parms; token; token = token->next) {
        newtoken = malloc(sizeof(idToken));
        idToken_InitWithToken(newtoken, token);
        newtoken->next = NULL;
        if (lasttoken) lasttoken->next = newtoken;
        else newdefine->parms = newtoken;
        lasttoken = newtoken;
    }
    return newdefine;
}

static void freeDefine(define_t *define) {
    idToken *t, *next;

    //free the define parameters
    for (t = define->parms; t; t = next) {
        next = t->next;
        free(t); // delete t;
    }
    //free the define tokens
    for (t = define->tokens; t; t = next) {
        next = t->next;
        free(t); // delete t;
    }
    //free the define
    free(define);
}

static define_t *defineFromString(const char *string) {
    idParser *src = [[idParser alloc] init];
    define_t *def;

    if (![src loadMemory:string length:strlen(string) name:@"*defineString" startLine:1 error:nil]) {
        return NULL;
    }
    // create a define from the source
    if (![src directive_define:nil]) {
        [src freeSource:YES];
        return NULL;
    }
    def = [src copyFirstDefine];
    [src freeSource:YES];
    //if the define was created succesfully
    return def;
}

-(void)error:(NSError **)error format:(NSString *)format, ... {
    va_list ap;

    va_start(ap, format);
    NSString *result = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);

    if (self->scriptstack) {
        [self->scriptstack error:error format:@"%@", result];
    }
}

-(void)warning:(NSString *)format, ... {
    va_list ap;

    va_start(ap, format);
    NSString *result = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);

    if (self->scriptstack) {
        [self->scriptstack warning:@"%@", result];
    }
}

-(void)pushIndent:(int)type skip:(int)skip {
    indent_t *indent;

//RAVEN BEGIN
//amccarthy: Added memory allocation tag
    indent = (indent_t *) malloc(sizeof(indent_t));
//RAVEN END
    indent->type = type;
    indent->script = self->scriptstack;
    indent->skip = (skip != 0);
    self->skip += indent->skip;
    indent->next = self->indentstack;
    self->indentstack = indent;
}

-(void)popIndent:(int *)type skip:(int *)skip {
    indent_t *indent;

    *type = 0;
    *skip = 0;

    indent = self->indentstack;
    if (!indent) return;

    // must be an indent from the current script
    if (self->indentstack->script != self->scriptstack) {
        return;
    }

    *type = indent->type;
    *skip = indent->skip;
    self->indentstack = self->indentstack->next;
    self->skip -= indent->skip;
    free(indent);
}

-(void)pushScript:(idLexer *)script {
    idLexer *s;

    for ( s = self->scriptstack; s; s = [s next]) {
        if ( [[s fileName] caseInsensitiveCompare:[script fileName]] == NSOrderedSame) {
            [self warning:@"'%@' recursively included", [script fileName]];
            return;
        }
    }
    //push the script on the script stack
    [script setNext:self->scriptstack];
    self->scriptstack = script;
}

-(BOOL)readSourceToken:(idToken *)token error:(NSError **)error {
    idToken *t;
    idLexer *script;
    int type, skip, changedScript;

    if (!self->scriptstack) {
        [self error:error format:@"readSourceToken: not loaded"];
        return NO;
    }
    changedScript = 0;
    // if there's no token already available
    while (!self->tokens) {
        // if there's a token to read from the script
        if ([self->scriptstack readToken:token error:error]) {
            token->linesCrossed += changedScript;

            // set the marker based on the start of the token read in
            if (!self->marker_p ) {
                self->marker_p = token->whiteSpaceEnd_p;
            }
            return YES;
        }
        // if at the end of the script
        if ([self->scriptstack endOfFile]) {
            // remove all indents of the script
            while (self->indentstack && self->indentstack->script == self->scriptstack ) {
                [self warning:@"missing #endif"];
                [self popIndent:&type skip:&skip];
            }
            changedScript = 1;
        }
        // if this was the initial script
        if (![self->scriptstack next]) {
            return NO;
        }
        // remove the script and return to the previous one
        script = self->scriptstack;
        self->scriptstack = [self->scriptstack next];
        script = nil; // delete script;
    }
    // copy the already available token
    idToken_AssignFromToken(token, self->tokens);
    // remove the token from the source
    t = self->tokens;
    self->tokens = self->tokens->next;
    free(t); //delete t;
    return true;
}

-(BOOL)unreadSourceToken:(idToken *)token {
    idToken *t = malloc(sizeof(idToken));

    idToken_InitWithToken(t, token);
    t->next = tokens;
    self->tokens = t;
    return YES;
}

-(BOOL)readDefine:(define_t *)define parms:(idToken **)parms maxParms:(int)maxparms error:(NSError **)error {
    define_t *newdefine;
    idToken token, *t, *last;
    int i, done, lastcomma, numparms, indent;

    idToken_Init(&token);
    if (![self readSourceToken:&token error:error]) {
        [self error:error format:@"define '%s' missing parameters", define->name];
        return NO;
    }

    if (define->numparms > maxparms) {
        [self error:error format:@"define with more than %d parameters", maxparms];
        return NO;
    }

    for ( i = 0; i < define->numparms; i++ ) {
        parms[i] = NULL;
    }
    // if no leading "("
    if (strcmp(token.text, "(")) {
        [self unreadSourceToken:&token];
        [self error:error format:@"define '%s' missing parameters", define->name];
        return NO;
    }
    // read the define parameters
    for ( done = 0, numparms = 0, indent = 1; !done; ) {
        if ( numparms >= maxparms ) {
            [self error:error format:@"define '%s' with too many parameters", define->name];
            return NO;
        }
        parms[numparms] = NULL;
        lastcomma = 1;
        last = NULL;
        while( !done ) {

            if (![self readSourceToken:&token error:error]) {
                [self error:error format:@"define '%s' incomplete", define->name];
                return NO;
            }

            if (!strcmp(token.text, ",")) {
                if (indent <= 1) {
                    if (lastcomma) {
                        [self warning:@"too many comma's"];
                    }
                    if (numparms >= define->numparms) {
                        [self warning:@"too many define parameters"];
                    }
                    lastcomma = 1;
                    break;
                }
            }
            else if (!strcmp(token.text, "(")) {
                indent++;
            }
            else if (!strcmp(token.text, ")")) {
                indent--;
                if (indent <= 0) {
                    if (!parms[define->numparms-1] ) {
                        [self warning:@"too few define parameters"];
                    }
                    done = 1;
                    break;
                }
            }
            else if (token.type == TT_NAME) {
                newdefine = findHashedDefine(self->definehash, token.text);
                if (newdefine) {
                    if (![self expandDefine:newdefine intoSource:&token error:error]) {
                        return NO;
                    }
                    continue;
                }
            }

            lastcomma = 0;

            if (numparms < define->numparms) {

                t = malloc(sizeof(idToken));
                idToken_InitWithToken(t, &token);
                t->next = NULL;
                if (last) last->next = t;
                else parms[numparms] = t;
                last = t;
            }
        }
        numparms++;
    }
    return YES;
}

static BOOL stringizeTokens(idToken *tokens, idToken *token) {
    idToken *t;

    token->type = TT_STRING;
    token->whiteSpaceStart_p = NULL;
    token->whiteSpaceEnd_p = NULL;
    token->text[0] = '\0';
    token->length = 0;

    for (t = tokens; t; t = t->next) {
        idToken_AppendToken(token, t);
    }

    return YES;
}

static BOOL mergeTokens(idToken *t1, idToken *t2) {
    // merging of a name with a name or number
    if (t1->type == TT_NAME && (t2->type == TT_NAME || (t2->type == TT_NUMBER && !(t2->subtype & TT_FLOAT))) ) {
        idToken_AppendToken(t1, t2);
        return YES;
    }
    // merging of two strings
    if (t1->type == TT_STRING && t2->type == TT_STRING) {
        idToken_AppendToken(t1, t2);
        return YES;
    }
    // merging of two numbers
    if (t1->type == TT_NUMBER && t2->type == TT_NUMBER &&
            !(t1->subtype & (TT_HEX|TT_BINARY)) && !(t2->subtype & (TT_HEX|TT_BINARY)) &&
            (!(t1->subtype & TT_FLOAT) || !(t2->subtype & TT_FLOAT)) ) {
        idToken_AppendToken(t1, t2);
        return YES;
    }

    return NO;
}

-(void)addBuiltinDefines {
    int i;
    define_t *define;
    struct builtin
    {
        const char *string;
        int id;
    } builtin[] = {
        { "__LINE__",    BUILTIN_LINE },
        { "__FILE__",    BUILTIN_FILE },
        { "__DATE__",    BUILTIN_DATE },
        { "__TIME__",    BUILTIN_TIME },
        { "__STDC__",    BUILTIN_STDC },
        { NULL, 0 }
    };

    for (i = 0; builtin[i].string; i++) {
//RAVEN BEGIN
//amccarthy: Added memory allocation tag
        define = (define_t *) malloc(sizeof(define_t) + strlen(builtin[i].string) + 1);
//RAVEN END
        define->name = (char *) define + sizeof(define_t);
        strcpy(define->name, builtin[i].string);
        define->flags = DEFINE_FIXED;
        define->builtin = builtin[i].id;
        define->numparms = 0;
        define->parms = NULL;
        define->tokens = NULL;
        // add the define to the source
        addDefineToHash(define, definehash);
    }
}

-(define_t *)copyFirstDefine {
    int i;

    for ( i = 0; i < DEFINEHASHSIZE; i++ ) {
        if ( definehash[i] ) {
            return copyDefine(definehash[i]);
        }
    }
    return NULL;
}

-(int)expandBuiltinDefine:(define_t *)define withToken:(idToken *)deftoken firstToken:(idToken **)firsttoken lastToken:(idToken **)lasttoken error:(NSError **)error {
    idToken *token = malloc(sizeof(idToken));

    idToken_InitWithToken(token, deftoken);
    switch (define->builtin) {
        case BUILTIN_LINE: {
            idToken_BuiltinLine(token, deftoken);
            *firsttoken = token;
            *lasttoken = token;
            break;
        }
        case BUILTIN_FILE: {
            idToken_BuiltinFile(token, [[self->scriptstack fileName] UTF8String], deftoken);
            *firsttoken = token;
            *lasttoken = token;
            break;
        }
        case BUILTIN_DATE: {
            idToken_BuiltinDate(token, deftoken);
            *firsttoken = token;
            *lasttoken = token;
            break;
        }
        case BUILTIN_TIME: {
            idToken_BuiltinTime(token, deftoken);
            *firsttoken = token;
            *lasttoken = token;
            break;
        }
        case BUILTIN_STDC: {
            [self warning:@"__STDC__ not supported"];
            *firsttoken = NULL;
            *lasttoken = NULL;
            break;
        }
        default: {
            *firsttoken = NULL;
            *lasttoken = NULL;
            break;
        }
    }
    return YES;
}

-(BOOL)expandToken:(idToken *)deftoken define:(define_t *)define firstToken:(idToken **)firsttoken lastToken:(idToken **)lasttoken error:(NSError **)error {
    idToken *parms[MAX_DEFINEPARMS], *dt, *pt, *t;
    idToken *t1, *t2, *first, *last, *nextpt, token;
    int parmnum, i;

    // if it is a builtin define
    if (define->builtin) {
        return [self expandBuiltinDefine:define withToken:deftoken firstToken:firsttoken lastToken:lasttoken error:error];
    }
    
    idToken_Init(&token);
    
    // if the define has parameters
    if (define->numparms) {
        if (![self readDefine:define parms:parms maxParms:MAX_DEFINEPARMS error:error]) {
            return NO;
        }
#ifdef DEBUG_EVAL
        for ( i = 0; i < define->numparms; i++ ) {
            NSLog(@"define parms %d:", i);
            for ( pt = parms[i]; pt; pt = pt->next ) {
                NSLog(@"%@", [pt string] );
            }
        }
#endif //DEBUG_EVAL
    }
    // empty list at first
    first = NULL;
    last = NULL;
    // create a list with tokens of the expanded define
    for (dt = define->tokens; dt; dt = dt->next) {
        parmnum = -1;
        // if the token is a name, it could be a define parameter
        if (dt->type == TT_NAME) {
            parmnum = findDefineParm(define, dt->text);
        }
        // if it is a define parameter
        if (parmnum >= 0) {
            for (pt = parms[parmnum]; pt; pt = pt->next) {
                t = malloc(sizeof(idToken));
                idToken_InitWithToken(t, pt);
                //add the token to the list
                t->next = NULL;
                if (last) last->next = t;
                else first = t;
                last = t;
            }
        }
        else {
            // if stringizing operator
            if (!strcmp(dt->text, "#")) {
                // the stringizing operator must be followed by a define parameter
                if (dt->next) {
                    parmnum = findDefineParm(define, dt->next->text);
                } else {
                    parmnum = -1;
                }

                if (parmnum >= 0) {
                    // step over the stringizing operator
                    dt = dt->next;
                    // stringize the define parameter tokens
                    if (!stringizeTokens(parms[parmnum], &token)) {
                        [self error:error format:@"can't stringize tokens"];
                        return NO;
                    }
                    t = malloc(sizeof(idToken));
                    idToken_InitWithToken(t, &token);
                } else {
                    [self warning:@"stringizing operator without define parameter"];
                    continue;
                }
            } else {
                t = malloc(sizeof(idToken));
                idToken_InitWithToken(t, dt);
                t->line = deftoken->line;
            }
            // add the token to the list
            t->next = NULL;
// the token being read from the define list should use the line number of
// the original file, not the header file
            t->line = deftoken->line;

            if (last) last->next = t;
            else first = t;
            last = t;
        }
    }
    // check for the merging operator
    for (t = first; t; ) {
        if (t->next) {
            // if the merging operator
            if (!strcmp(t->next->text, "##")) {
                t1 = t;
                t2 = t->next->next;
                if (t2) {
                    if (!mergeTokens(t1, t2)) {
                        [self error:error format:@"can't merge '%s' with '%s'", t1->text, t2->text];
                        return NO;
                    }
                    free(t1->next); // delete t1->next;
                    t1->next = t2->next;
                    if (t2 == last) last = t1;
                    free(t2); // delete t2;
                    continue;
                }
            }
        }
        t = t->next;
    }
    // store the first and last token of the list
    *firsttoken = first;
    *lasttoken = last;
    // free all the parameter tokens
    for (i = 0; i < define->numparms; i++) {
        for (pt = parms[i]; pt; pt = nextpt) {
            nextpt = pt->next;
            free(pt); // delete pt;
        }
    }

    return YES;
}

-(BOOL)expandDefine:(define_t *)define intoSource:(idToken *)deftoken error:(NSError **)error {
    idToken *firsttoken, *lasttoken;

    if ( ![self expandToken:deftoken define:define firstToken:&firsttoken lastToken:&lasttoken error:error]) {
        return NO;
    }
    // if the define is not empty
    if (firsttoken && lasttoken) {
        firsttoken->linesCrossed += deftoken->linesCrossed;
        lasttoken->next = self->tokens;
        self->tokens = firsttoken;
    }
    return YES;
}

-(BOOL)readLine:(idToken *)token error:(NSError **)error {
    int crossline;

    crossline = 0;
    do {
        if (![self readSourceToken:token error:error]) {
            return NO;
        }
        
        if (token->linesCrossed > crossline) {
            [self unreadSourceToken:token];
            return NO;
        }
        crossline = 1;
    } while (!strcmp(token->text, "\\"));
    return YES;
}

-(BOOL)directive_include:(NSError **)error {
    idLexer *script;
    idToken token;
    NSMutableString *path = [[NSMutableString alloc] init];
    
    idToken_Init(&token);

    if (![self readSourceToken:&token error:error]) {
        [self error:error format:@"#include without file name"];
        return NO;
    }
    if (token.linesCrossed > 0 ) {
        [self error:error format:@"#include without file name"];
        return NO;
    }
    if (token.type == TT_STRING) {
        script = [[idLexer alloc] initWithFileSystem:self.fileSystem];
        // try relative to the current file
        NSMutableString *basePath = [[scriptstack fileName] mutableCopy];
        [basePath backSlashesToSlashes];
        // strip filename
        [basePath setString:[basePath stringByDeletingLastPathComponent]];

        // Normalize to a game-relative path to avoid absolute OS/pk4 paths in includes.
        NSMutableString *relBase = [basePath mutableCopy];
        NSRange pakPos = [relBase rangeOfString:@".pk4/"];
        if (pakPos.location != NSNotFound) {
            NSUInteger afterPakPos = NSMaxRange(pakPos);
            NSRange rangeToDelete = NSMakeRange(0, afterPakPos);
            [relBase deleteCharactersInRange:rangeToDelete];
        } else {
            NSString *rel = [self.fileSystem osPathToRelativePath:relBase];
            if ([rel length]) {
                relBase = [rel mutableCopy];
            }
        }

        [relBase stripTrailingChar:'/'];
        [relBase stripTrailingChar:'\\'];

        NSMutableString *tokenStr = [NSMutableString stringWithCString:token.text];
        [tokenStr backSlashesToSlashes];

        if ([relBase length]) {
            [relBase appendString:@"/"];
            // Avoid duplicate prefixes when the include already starts with the base path.
            if ([tokenStr compare:relBase options:NSCaseInsensitiveSearch range:NSMakeRange(0, [relBase length])] == NSOrderedSame) {
                path = tokenStr;
            } else {
                path = relBase;
                [path appendString:tokenStr];
            }
        } else {
            path = tokenStr;
        }

        if (![script loadFile:path isOSPath:OSPath error:error]) {
            // try absolute path
            path = [NSMutableString stringWithCString:token.text];
            if (![script loadFile:path isOSPath:OSPath error:error]) {
                // try from the include path
                path = [NSMutableString stringWithFormat:@"%@%s", includepath, token.text];
                if (![script loadFile:path isOSPath:OSPath error:error]) {
                    script = nil; // delete script;
                }
            }
        }
    } else if (token.type == TT_PUNCTUATION && !strcmp(token.text, "<")) {
        path = [includepath mutableCopy];
        while ([self readSourceToken:&token error:error]) {
            if (token.linesCrossed > 0 ) {
                [self unreadSourceToken:&token];
                break;
            }
            if (token.type == TT_PUNCTUATION && !strcmp(token.text, ">")) {
                break;
            }
            [path appendFormat:@"%s", token.text];
        }
        if (strcmp(token.text, ">")) {
            [self warning:@"#include missing trailing >"];
        }
        if (![path length]) {
            [self error:error format:@"#include without file name between < >"];
            return NO;
        }
        if (self->flags & LEXFL_NOBASEINCLUDES) {
            return YES;
        }
        script = [[idLexer alloc] initWithFileSystem:self.fileSystem];
        if (![script loadFile:[includepath stringByAppendingString:path] isOSPath:OSPath error:error]) {
            script = nil; // delete script;
        }
    } else {
        [self error:error format:@"#include without file name"];
        return NO;
    }
    if (!script) {
        [self error:error format:@"file '%@' not found", path];
        return NO;
    }
    [script setFlags:self->flags];
    [script setPunctuations:self->punctuations];
    [self pushScript:script];
    return YES;
}

-(BOOL)directive_undef:(NSError **)error {
    idToken token;
    define_t *define, *lastdefine;
    int hash;
    
    idToken_Init(&token);

    //
    if (![self readLine:&token error:error]) {
        [self error:error format:@"undef without name"];
        return NO;
    }
    if (token.type != TT_NAME) {
        [self unreadSourceToken:&token];
        [self error:error format:@"expected name but found '%s'", token.text];
        return NO;
    }

    hash = PC_NameHash(token.text);
    for (lastdefine = NULL, define = self->definehash[hash]; define; define = define->hashnext) {
        if (!strcmp(define->name, token.text)) {
            if (define->flags & DEFINE_FIXED) {
                [self warning:@"can't undef '%s'", token.text];
            } else {
                if (lastdefine) {
                    lastdefine->hashnext = define->hashnext;
                } else {
                    self->definehash[hash] = define->hashnext;
                }
                freeDefine(define);
            }
            break;
        }
        lastdefine = define;
    }
    return YES;
}

-(BOOL)directive_define:(NSError **)error {
    idToken token, *t, *last;
    define_t *define;

    idToken_Init(&token);
    if (![self readLine:&token error:error]) {
        [self error:error format:@"#define without name"];
        return NO;
    }
    if (token.type != TT_NAME) {
        [self unreadSourceToken:&token];
        [self error:error format:@"expected name after #define, found '%s'", token.text];
        return NO;
    }
    // check if the define already exists
    define = findHashedDefine(self->definehash, token.text);
    if (define) {
        if (define->flags & DEFINE_FIXED) {
            [self error:error format:@"can't redefine '%s'", token.text];
            return NO;
        }
        [self warning:@"redefinition of '%s'", token.text];
        // unread the define name before executing the #undef directive
        [self unreadSourceToken:&token];
        if (![self directive_undef:error]) {
            return NO;
        }
        // if the define was not removed (define->flags & DEFINE_FIXED)
        define = findHashedDefine(self->definehash, token.text);
    }
    // allocate define
//RAVEN BEGIN
//amccarthy: Added memory allocation tag
    define = (define_t *) calloc(sizeof(define_t) + token.length+ 1, 1);
//RAVEN END
    define->name = (char *) define + sizeof(define_t);
    strcpy(define->name, token.text);
    // add the define to the source
    addDefineToHash(define, self->definehash);
    // if nothing is defined, just return
    if (![self readLine:&token error:error]) {
        return YES;
    }
    // if it is a define with parameters
    if (idToken_WhiteSpaceBeforeToken(&token) == 0 && !strcmp(token.text, "(")) {
        // read the define parameters
        last = NULL;
        if (![self checkTokenString:@")" error:error]) {
            while(1) {
                if (![self readLine:&token error:error]) {
                    [self error:error format:@"expected define parameter"];
                    return NO;
                }
                // if it isn't a name
                if (token.type != TT_NAME) {
                    [self error:error format:@"invalid define parameter"];
                    return NO;
                }

                if (findDefineParm(define, token.text) >= 0) {
                    [self error:error format:@"two the same define parameters"];
                    return NO;
                }
                // add the define parm
                t = malloc(sizeof(idToken));
                idToken_InitWithToken(t, &token);
                idToken_ClearTokenWhiteSpace(t);
                t->next = NULL;
                if (last) last->next = t;
                else define->parms = t;
                last = t;
                define->numparms++;
                // read next token
                if (![self readLine:&token error:error]) {
                    [self error:error format:@"define parameters not terminated"];
                    return NO;
                }

                if (!strcmp(token.text, ")")) {
                    break;
                }
                // then it must be a comma
                if (strcmp(token.text, ",")) {
                    [self error:error format:@"define not terminated"];
                    return NO;
                }
            }
        }
        if (![self readLine:&token error:error]) {
            return YES;
        }
    }
    // read the defined stuff
    last = nil;
    do
    {
        t = malloc(sizeof(idToken));
        idToken_InitWithToken(t, &token);
        if (t->type == TT_NAME && !strcmp(t->text, define->name)) {
            t->flags |= TOKEN_FL_RECURSIVE_DEFINE;
            [self warning:@"recursive define (removed recursion)"];
        }
        idToken_ClearTokenWhiteSpace(t);
        t->next = NULL;
        if (last) last->next = t;
        else define->tokens = t;
        last = t;
    } while ([self readLine:&token error:error]);

    if (last) {
        // check for merge operators at the beginning or end
        if (!strcmp(define->tokens->text, "##") || !strcmp(last->text, "##")) {
            [self error:error format:@"define with misplaced ##"];
            return NO;
        }
    }
    return YES;
}

-(BOOL)addDefine:(NSString *)string {
    define_t *define;

    define = defineFromString([string UTF8String]);
    if (!define) {
        return NO;
    }
    addDefineToHash(define, self->definehash);
    return YES;
}

-(void)addGlobalDefinesToSource {
    define_t *define, *newdefine;

    for (define = globaldefines; define; define = define->next) {
        newdefine = copyDefine( define );
        addDefineToHash(newdefine, self->definehash);
    }
}

-(BOOL)directive_if_def:(int)type error:(NSError **)error {
    idToken token;
    define_t *d;
    int skip;

    idToken_Init(&token);
    if (![self readLine:&token error:error]) {
        [self error:error format:@"#ifdef without name"];
        return NO;
    }
    if (token.type != TT_NAME) {
        [self unreadSourceToken:&token];
        [self error:error format:@"expected name after #ifdef, found '%s'", token.text];
        return NO;
    }
    d = findHashedDefine(self->definehash, token.text);
    skip = (type == INDENT_IFDEF) == (d == NULL);
    [self pushIndent:type skip:skip];
    return YES;
}

-(BOOL)directive_ifdef:(NSError **)error {
    return [self directive_if_def:INDENT_IFDEF error:error];
}

-(BOOL)directive_ifndef:(NSError **)error {
    return [self directive_if_def:INDENT_IFNDEF error:error];
}

-(BOOL)directive_else:(NSError **)error {
    int type, skip;

    [self popIndent:&type skip:&skip];
    if (!type) {
        [self error:error format:@"misplaced #else"];
        return NO;
    }
    if (type == INDENT_ELSE) {
        [self error:error format:@"#else after #else"];
        return NO;
    }
    [self pushIndent:INDENT_ELSE skip:!skip];
    return YES;
}

-(BOOL)directive_endif:(NSError **)error {
    int type, skip;

    [self popIndent:&type skip:&skip];
    if (!type) {
        [self error:error format:@"misplaced #endif"];
        return NO;
    }
    return YES;
}

typedef struct operator_s
{
    int op;
    int priority;
    int parentheses;
    struct operator_s *prev, *next;
} operator_t;

typedef struct value_s
{
    signed long int intvalue;
    double floatvalue;
    int parentheses;
    struct value_s *prev, *next;
} value_t;

int PC_OperatorPriority(int op) {
    switch(op) {
        case P_MUL: return 15;
        case P_DIV: return 15;
        case P_MOD: return 15;
        case P_ADD: return 14;
        case P_SUB: return 14;

        case P_LOGIC_AND: return 7;
        case P_LOGIC_OR: return 6;
        case P_LOGIC_GEQ: return 12;
        case P_LOGIC_LEQ: return 12;
        case P_LOGIC_EQ: return 11;
        case P_LOGIC_UNEQ: return 11;

        case P_LOGIC_NOT: return 16;
        case P_LOGIC_GREATER: return 12;
        case P_LOGIC_LESS: return 12;

        case P_RSHIFT: return 13;
        case P_LSHIFT: return 13;

        case P_BIN_AND: return 10;
        case P_BIN_OR: return 8;
        case P_BIN_XOR: return 9;
        case P_BIN_NOT: return 16;

        case P_COLON: return 5;
        case P_QUESTIONMARK: return 5;
    }
    return false;
}

//#define AllocValue()            GetClearedMemory(sizeof(value_t));
//#define FreeValue(val)        FreeMemory(val)
//#define AllocOperator(op)        op = (operator_t *) GetClearedMemory(sizeof(operator_t));
//#define FreeOperator(op)        FreeMemory(op);

#define MAX_VALUES        64
#define MAX_OPERATORS    64

#define AllocValue(val)                                    \
    if ( numvalues >= MAX_VALUES ) {                       \
        [self error:error format:@"out of value space\n"]; \
        err = YES;                                         \
        break;                                             \
    } else {                                               \
        val = &value_heap[numvalues++];                    \
    }

#define FreeValue(val)

#define AllocOperator(op)                                    \
    if (numoperators >= MAX_OPERATORS) {                     \
        [self error:error format:@"out of operator space\n"];\
        err = YES;                                           \
        break;                                               \
    } else {                                                 \
        op = &operator_heap[numoperators++];                 \
    }

#define FreeOperator(op)

-(BOOL)evaluateTokens:(idToken *)tokens intvalue:(signed long int *)intvalue floatvalue:(double *)floatvalue integer:(int)integer error:(NSError **)error {
    operator_t *o, *firstoperator, *lastoperator;
    value_t *v, *firstvalue, *lastvalue, *v1, *v2;
    idToken *t;
    BOOL brace = NO;
    int parentheses = 0;
    BOOL err = NO;
    BOOL lastwasvalue = NO;
    BOOL negativevalue = NO;
    int questmarkintvalue = 0;
    double questmarkfloatvalue = 0;
    BOOL gotquestmarkvalue = NO;
    int lastoperatortype = 0;
    //
    operator_t operator_heap[MAX_OPERATORS];
    int numoperators = 0;
    value_t value_heap[MAX_VALUES];
    int numvalues = 0;

    firstoperator = lastoperator = NULL;
    firstvalue = lastvalue = NULL;
    if (intvalue) *intvalue = 0;
    if (floatvalue) *floatvalue = 0;
    for (t = tokens; t; t = t->next) {
        switch (t->type) {
            case TT_NAME:
            {
                if (lastwasvalue || negativevalue) {
                    [self error:error format:@"syntax error in #if/#elif"];
                    err = YES;
                    break;
                }
                if (strcmp(t->text, "defined")) {
                    [self error:error format:@"undefined name '%s' in #if/#elif", t->text];
                    err = YES;
                    break;
                }
                t = t->next;
                if (!strcmp(t->text, "(")) {
                    brace = YES;
                    t = t->next;
                }
                if (!t || t->type != TT_NAME) {
                    [self error:error format:@"defined() without name in #if/#elif"];
                    err = YES;
                    break;
                }
                //v = (value_t *) GetClearedMemory(sizeof(value_t));
                AllocValue(v);
                if (findHashedDefine(self->definehash, t->text)) {
                    v->intvalue = 1;
                    v->floatvalue = 1;
                }
                else {
                    v->intvalue = 0;
                    v->floatvalue = 0;
                }
                v->parentheses = parentheses;
                v->next = NULL;
                v->prev = lastvalue;
                if (lastvalue) lastvalue->next = v;
                else firstvalue = v;
                lastvalue = v;
                if (brace) {
                    t = t->next;
                    if (!t || strcmp(t->text, ")")) {
                        [self error:error format:@"defined missing ) in #if/#elif"];
                        err = YES;
                        break;
                    }
                }
                brace = NO;
                // defined() creates a value
                lastwasvalue = YES;
                break;
            }
            case TT_NUMBER:
            {
                if (lastwasvalue) {
                    [self error:error format:@"syntax error in #if/#elif"];
                    err = YES;
                    break;
                }
                //v = (value_t *) GetClearedMemory(sizeof(value_t));
                AllocValue(v);
                if (negativevalue) {
                    v->intvalue = -idToken_IntValue(t);
                    v->floatvalue = -idToken_FloatValue(t);
                }
                else {
                    v->intvalue = idToken_IntValue(t);
                    v->floatvalue = idToken_FloatValue(t);
                }
                v->parentheses = parentheses;
                v->next = NULL;
                v->prev = lastvalue;
                if (lastvalue) lastvalue->next = v;
                else firstvalue = v;
                lastvalue = v;
                //last token was a value
                lastwasvalue = YES;
                //
                negativevalue = NO;
                break;
            }
            case TT_PUNCTUATION:
            {
                if (negativevalue) {
                    [self error:error format:@"misplaced minus sign in #if/#elif"];
                    err = YES;
                    break;
                }
                if (t->subtype == P_PARENTHESESOPEN) {
                    parentheses++;
                    break;
                }
                else if (t->subtype == P_PARENTHESESCLOSE) {
                    parentheses--;
                    if (parentheses < 0) {
                        [self error:error format:@"too many ) in #if/#elsif"];
                        err = YES;
                    }
                    break;
                }
                //check for invalid operators on floating point values
                if ( !integer ) {
                    if (t->subtype == P_BIN_NOT || t->subtype == P_MOD ||
                        t->subtype == P_RSHIFT  || t->subtype == P_LSHIFT ||
                        t->subtype == P_BIN_AND || t->subtype == P_BIN_OR ||
                        t->subtype == P_BIN_XOR) {
                        [self error:error format:@"illegal operator '%s' on floating point operands\n", t->text];
                        err = YES;
                        break;
                    }
                }
                switch (t->subtype) {
                    case P_LOGIC_NOT:
                    case P_BIN_NOT:
                    {
                        if (lastwasvalue) {
                            [self error:error format:@"! or ~ after value in #if/#elif"];
                            err = YES;
                            break;
                        }
                        break;
                    }
                    case P_INC:
                    case P_DEC:
                    {
                        [self error:error format:@"++ or -- used in #if/#elif"];
                        break;
                    }
                    case P_SUB:
                    {
                        if (!lastwasvalue) {
                            negativevalue = YES;
                            break;
                        }
                    }
                    
                    case P_MUL:
                    case P_DIV:
                    case P_MOD:
                    case P_ADD:

                    case P_LOGIC_AND:
                    case P_LOGIC_OR:
                    case P_LOGIC_GEQ:
                    case P_LOGIC_LEQ:
                    case P_LOGIC_EQ:
                    case P_LOGIC_UNEQ:

                    case P_LOGIC_GREATER:
                    case P_LOGIC_LESS:

                    case P_RSHIFT:
                    case P_LSHIFT:

                    case P_BIN_AND:
                    case P_BIN_OR:
                    case P_BIN_XOR:

                    case P_COLON:
                    case P_QUESTIONMARK:
                    {
                        if (!lastwasvalue) {
                            [self error:error format:@"operator '%s' after operator in #if/#elif", t->text];
                            err = YES;
                            break;
                        }
                        break;
                    }
                    default:
                    {
                        [self error:error format:@"invalid operator '%s' in #if/#elif", t->text];
                        err = YES;
                        break;
                    }
                }
                if (!err && !negativevalue) {
                    //o = (operator_t *) GetClearedMemory(sizeof(operator_t));
                    AllocOperator(o);
                    o->op = t->subtype;
                    o->priority = PC_OperatorPriority(o->op);
                    o->parentheses = parentheses;
                    o->next = NULL;
                    o->prev = lastoperator;
                    if (lastoperator) lastoperator->next = o;
                    else firstoperator = o;
                    lastoperator = o;
                    lastwasvalue = NO;
                }
                break;
            }
            default:
            {
                [self error:error format:@"unknown '%s' in #if/#elif", t->text];
                err = YES;
                break;
            }
        }
        if (err) {
            break;
        }
    }
    if (!err) {
        if (!lastwasvalue) {
            [self error:error format:@"trailing operator in #if/#elif"];
            err = YES;
        }
        else if (parentheses) {
            [self error:error format:@"too many ( in #if/#elif"];
            err = YES;
        }
    }
    //
    gotquestmarkvalue = NO;
    questmarkintvalue = 0;
    questmarkfloatvalue = 0;
    //while there are operators
    while (!err && firstoperator) {
        v = firstvalue;
        for (o = firstoperator; o->next; o = o->next) {
            //if the current operator is nested deeper in parentheses
            //than the next operator
            if (o->parentheses > o->next->parentheses) {
                break;
            }
            //if the current and next operator are nested equally deep in parentheses
            if (o->parentheses == o->next->parentheses) {
                //if the priority of the current operator is equal or higher
                //than the priority of the next operator
                if (o->priority >= o->next->priority) {
                    break;
                }
            }
            //if the arity of the operator isn't equal to 1
            if (o->op != P_LOGIC_NOT && o->op != P_BIN_NOT) {
                v = v->next;
            }
            //if there's no value or no next value
            if (!v) {
                [self error:error format:@"missing values in #if/#elif"];
                err = YES;
                break;
            }
        }
        if (err) {
            break;
        }
        v1 = v;
        v2 = v->next;
#ifdef DEBUG_EVAL
        if (integer) {
            NSLog(@"operator %s, value1 = %d", [self->scriptstack punctuationFromId:o->op], v1->intvalue);
            if (v2) NSLog("value2 = %d", v2->intvalue);
        }
        else {
            NSLog("operator %s, value1 = %f", [self->scriptstack punctuationFromId:o->op], v1->floatvalue);
            if (v2) NSLog("value2 = %f", v2->floatvalue);
        }
#endif //DEBUG_EVAL
        switch(o->op) {
            case P_LOGIC_NOT:       v1->intvalue = !v1->intvalue;
                                    v1->floatvalue = !v1->floatvalue; break;
            case P_BIN_NOT:         v1->intvalue = ~v1->intvalue; break;
            case P_MUL:             v1->intvalue *= v2->intvalue;
                                    v1->floatvalue *= v2->floatvalue; break;
            case P_DIV:             if (!v2->intvalue || !v2->floatvalue)
                                    {
                                        [self error:error format:@"divide by zero in #if/#elif"];
                                        err = YES;
                                        break;
                                    }
                                    v1->intvalue /= v2->intvalue;
                                    v1->floatvalue /= v2->floatvalue; break;
            case P_MOD:             if (!v2->intvalue)
                                    {
                                        [self error:error format:@"divide by zero in #if/#elif"];
                                        err = YES;
                                        break;
                                    }
                                    v1->intvalue %= v2->intvalue; break;
            case P_ADD:             v1->intvalue += v2->intvalue;
                                    v1->floatvalue += v2->floatvalue; break;
            case P_SUB:             v1->intvalue -= v2->intvalue;
                                    v1->floatvalue -= v2->floatvalue; break;
            case P_LOGIC_AND:       v1->intvalue = v1->intvalue && v2->intvalue;
                                    v1->floatvalue = v1->floatvalue && v2->floatvalue; break;
            case P_LOGIC_OR:        v1->intvalue = v1->intvalue || v2->intvalue;
                                    v1->floatvalue = v1->floatvalue || v2->floatvalue; break;
            case P_LOGIC_GEQ:       v1->intvalue = v1->intvalue >= v2->intvalue;
                                    v1->floatvalue = v1->floatvalue >= v2->floatvalue; break;
            case P_LOGIC_LEQ:       v1->intvalue = v1->intvalue <= v2->intvalue;
                                    v1->floatvalue = v1->floatvalue <= v2->floatvalue; break;
            case P_LOGIC_EQ:        v1->intvalue = v1->intvalue == v2->intvalue;
                                    v1->floatvalue = v1->floatvalue == v2->floatvalue; break;
            case P_LOGIC_UNEQ:      v1->intvalue = v1->intvalue != v2->intvalue;
                                    v1->floatvalue = v1->floatvalue != v2->floatvalue; break;
            case P_LOGIC_GREATER:   v1->intvalue = v1->intvalue > v2->intvalue;
                                    v1->floatvalue = v1->floatvalue > v2->floatvalue; break;
            case P_LOGIC_LESS:      v1->intvalue = v1->intvalue < v2->intvalue;
                                    v1->floatvalue = v1->floatvalue < v2->floatvalue; break;
            case P_RSHIFT:          v1->intvalue >>= v2->intvalue; break;
            case P_LSHIFT:          v1->intvalue <<= v2->intvalue; break;
            case P_BIN_AND:         v1->intvalue &= v2->intvalue; break;
            case P_BIN_OR:          v1->intvalue |= v2->intvalue; break;
            case P_BIN_XOR:         v1->intvalue ^= v2->intvalue; break;
            case P_COLON:
            {
                if (!gotquestmarkvalue) {
                    [self error:error format:@": without ? in #if/#elif"];
                    err = YES;
                    break;
                }
                if (integer) {
                    if (!questmarkintvalue)
                        v1->intvalue = v2->intvalue;
                }
                else {
                    if (!questmarkfloatvalue)
                        v1->floatvalue = v2->floatvalue;
                }
                gotquestmarkvalue = NO;
                break;
            }
            case P_QUESTIONMARK:
            {
                if (gotquestmarkvalue) {
                    [self error:error format:@"? after ? in #if/#elif"];
                    err = YES;
                    break;
                }
                questmarkintvalue = v1->intvalue;
                questmarkfloatvalue = v1->floatvalue;
                gotquestmarkvalue = YES;
                break;
            }
        }
#ifdef DEBUG_EVAL
        if (integer) NSLog("result value = %d", v1->intvalue);
        else NSLog("result value = %f", v1->floatvalue);
#endif //DEBUG_EVAL
        if (err)
            break;
        lastoperatortype = o->op;
        //if not an operator with arity 1
        if (o->op != P_LOGIC_NOT && o->op != P_BIN_NOT) {
            //remove the second value if not question mark operator
            if (o->op != P_QUESTIONMARK) {
                v = v->next;
            }
            //
            if (v->prev) v->prev->next = v->next;
            else firstvalue = v->next;
            if (v->next) v->next->prev = v->prev;
            else lastvalue = v->prev;
            //FreeMemory(v);
            FreeValue(v);
        }
        //remove the operator
        if (o->prev) o->prev->next = o->next;
        else firstoperator = o->next;
        if (o->next) o->next->prev = o->prev;
        else lastoperator = o->prev;
        //FreeMemory(o);
        FreeOperator(o);
    }
    if (firstvalue) {
        if (intvalue) *intvalue = firstvalue->intvalue;
        if (floatvalue) *floatvalue = firstvalue->floatvalue;
    }
    for (o = firstoperator; o; o = lastoperator) {
        lastoperator = o->next;
        //FreeMemory(o);
        FreeOperator(o);
    }
    for (v = firstvalue; v; v = lastvalue) {
        lastvalue = v->next;
        //FreeMemory(v);
        FreeValue(v);
    }
    if (!err) {
        return YES;
    }
    if (intvalue) {
        *intvalue = 0;
    }
    if (floatvalue) {
        *floatvalue = 0;
    }
    return NO;
}

-(BOOL)evaluate:(signed long int *)intvalue floatvalue:(double *)floatvalue integer:(int)integer error:(NSError **)error {
    idToken token, *firsttoken, *lasttoken;
    idToken *t, *nexttoken;
    define_t *define;
    BOOL defined = NO;
    
    idToken_Init(&token);

    if (intvalue) {
        *intvalue = 0;
    }
    if (floatvalue) {
        *floatvalue = 0;
    }
    //
    if (![self readLine:&token error:error]) {
        [self error:error format:@"no value after #if/#elif"];
        return NO;
    }
    firsttoken = nil;
    lasttoken = nil;
    do {
        //if the token is a name
        if (token.type == TT_NAME) {
            if (defined) {
                defined = false;
                t = malloc(sizeof(idToken));
                idToken_InitWithToken(t, &token);
                t->next = NULL;
                if (lasttoken) lasttoken->next = t;
                else firsttoken = t;
                lasttoken = t;
            }
            else if (!strcmp(token.text, "defined")) {
                defined = YES;
                t = malloc(sizeof(idToken));
                idToken_InitWithToken(t, &token);
                t->next = NULL;
                if (lasttoken) lasttoken->next = t;
                else firsttoken = t;
                lasttoken = t;
            } else {
                //then it must be a define
                define = findHashedDefine(self->definehash, token.text);
                if (!define) {
                    [self error:error format:@"can't Evaluate '%s', not defined", token.text];
                    return NO;
                }
                if (![self expandDefine:define intoSource:&token error:error]) {
                    return NO;
                }
            }
        }
        //if the token is a number or a punctuation
        else if (token.type == TT_NUMBER || token.type == TT_PUNCTUATION) {
            t = malloc(sizeof(idToken));
            idToken_InitWithToken(t, &token);
            t->next = NULL;
            if (lasttoken) lasttoken->next = t;
            else firsttoken = t;
            lasttoken = t;
        } else {
            [self error:error format:@"can't Evaluate '%s'", token.text];
            return NO;
        }
    } while ([self readLine:&token error:error]);
    //
    if (![self evaluateTokens:firsttoken intvalue:intvalue floatvalue:floatvalue integer:integer error:error]) {
        return NO;
    }
    //
#ifdef DEBUG_EVAL
    NSLog(@"eval:");
#endif //DEBUG_EVAL
    for (t = firsttoken; t; t = nexttoken) {
#ifdef DEBUG_EVAL
        Log_Write(@" %s", t->text);
#endif //DEBUG_EVAL
        nexttoken = t->next;
        t = nil; // delete t;
    } //end for
#ifdef DEBUG_EVAL
    if (integer) NSLog(@"eval result: %d", *intvalue);
    else NSLog(@"eval result: %f", *floatvalue);
#endif //DEBUG_EVAL
    //
    return YES;
}

-(BOOL)dollarEvaluate:(signed long int *)intvalue floatvalue:(double *)floatvalue integer:(int)integer error:(NSError **)error {
    int indent;
    BOOL defined = NO;
    idToken token, *firsttoken, *lasttoken;
    idToken *t, *nexttoken;
    define_t *define;

    if (intvalue) {
        *intvalue = 0;
    }
    if (floatvalue) {
        *floatvalue = 0;
    }
    //
    idToken_Init(&token);
    if (![self readSourceToken:&token error:error]) {
        [self error:error format:@"no leading ( after $evalint/$evalfloat"];
        return NO;
    }
    if (![self readSourceToken:&token error:error]) {
        [self error:error format:@"nothing to Evaluate"];
        return NO;
    }
    indent = 1;
    firsttoken = NULL;
    lasttoken = NULL;
    do {
        //if the token is a name
        if (token.type == TT_NAME) {
            if (defined) {
                defined = NO;
                t = malloc(sizeof(idToken));
                idToken_InitWithToken(t, &token);
                t->next = NULL;
                if (lasttoken) lasttoken->next = t;
                else firsttoken = t;
                lasttoken = t;
            } else if (!strcmp(token.text, "defined")) {
                defined = YES;
                t = malloc(sizeof(idToken));
                idToken_InitWithToken(t, &token);
                t->next = NULL;
                if (lasttoken) lasttoken->next = t;
                else firsttoken = t;
                lasttoken = t;
            } else {
                //then it must be a define
                define = findHashedDefine(self->definehash, token.text);
                if (!define) {
                    [self warning:@"can't Evaluate '%s', not defined", token.text];
                    return NO;
                }
                if (![self expandDefine:define intoSource:&token error:error]) {
                    return NO;
                }
            }
        }
        //if the token is a number or a punctuation
        else if (token.type == TT_NUMBER || token.type == TT_PUNCTUATION) {
            if (token.text[0] == '(') indent++;
            else if (token.text[0] == ')') indent--;
            if (indent <= 0) {
                break;
            }
            t = malloc(sizeof(idToken));
            idToken_InitWithToken(t, &token);
            t->next = NULL;
            if (lasttoken) lasttoken->next = t;
            else firsttoken = t;
            lasttoken = t;
        } else {
            [self error:error format:@"can't Evaluate '%s'", token.type];
            return NO;
        }
    } while ([self readSourceToken:&token error:error]);
    //
    if (![self evaluateTokens:firsttoken intvalue:intvalue floatvalue:floatvalue integer:integer error:error]) {
        return NO;
    }
    //
#ifdef DEBUG_EVAL
    NSLog(@"$eval:");
#endif //DEBUG_EVAL
    for (t = firsttoken; t; t = nexttoken) {
#ifdef DEBUG_EVAL
        NSLog(@" %@", [t string]);
#endif //DEBUG_EVAL
        nexttoken = t->next;
        t = nil; // delete t;
    } //end for
#ifdef DEBUG_EVAL
    if (integer) NSLog(@"$eval result: %d", *intvalue);
    else NSLog(@"$eval result: %f", *floatvalue);
#endif //DEBUG_EVAL
    //
    return YES;
}

-(BOOL)directive_elif:(NSError **)error {
    signed long int value;
    int type, skip;

    [self popIndent:&type skip:&skip];
    if (!type || type == INDENT_ELSE) {
        [self error:error format:@"misplaced #elif"];
        return NO;
    }
    if (![self evaluate:&value floatvalue:NULL integer:1 error:error]) {
        return NO;
    }
    skip = (value == 0);
    [self pushIndent:INDENT_ELIF skip:skip];
    return YES;
}

-(BOOL)directive_if:(NSError **)error {
    signed long int value;
    int skip;
    
    if (![self evaluate:&value floatvalue:NULL integer:1 error:error]) {
        return NO;
    }
    skip = (value == 0);
    [self pushIndent:INDENT_IF skip:skip];
    return YES;
}

-(BOOL)directive_line:(NSError **)error {
    idToken token;

    idToken_Init(&token);
    [self error:error format:@"#line directive not supported"];
    while ([self readLine:&token error:error]) {
    }
    return YES;
}

-(BOOL)directive_error:(NSError **)error {
    idToken token;

    idToken_Init(&token);
    if ( ![self readLine:&token error:error] || token.type != TT_STRING) {
        [self error:error format:@"#error without string"];
        return NO;
    }
    [self error:error format:@"#error: %s", token.type];
    return YES;
}

-(BOOL)directive_warning:(NSError **)error {
    idToken token;

    idToken_Init(&token);
    if (![self readLine:&token error:error] || token.type != TT_STRING) {
        [self warning:@"#warning without string"];
        return NO;
    }
    [self warning:@"#warning: %s", token.text];
    return YES;
}

-(BOOL)directive_pragma:(NSError **)error {
    idToken token;

    idToken_Init(&token);
    [self warning:@"#pragma directive not supported"];
    while ([self readLine:&token error:error]) {
    }
    return YES;
}

-(void)unreadSignToken {
    idToken token;
    
    idToken_Init(&token);
    token.whiteSpaceStart_p = NULL;
    token.whiteSpaceEnd_p = NULL;
    token.line = [self->scriptstack lineNum];
    token.linesCrossed = 0;
    token.flags = 0;
    idToken_AssignFromString(&token, "-");
    token.type = TT_PUNCTUATION;
    token.subtype = P_SUB;
    [self unreadSourceToken:&token];
}

-(BOOL)directive_eval:(NSError **)error {
    signed long int value;
    
    if (![self evaluate:&value floatvalue:NULL integer:1 error:error]) {
        return NO;
    }

    idToken token;

    idToken_Init(&token);
    token.whiteSpaceStart_p = NULL;
    token.whiteSpaceEnd_p = NULL;
    token.line = [self->scriptstack lineNum];
    token.linesCrossed = 0;
    token.flags = 0;
    idToken_AssignFromInt(&token, value);

    [self unreadSourceToken:&token];
    if ( value < 0 ) {
        [self unreadSignToken];
    }
    return YES;
}

-(BOOL)directive_evalfloat:(NSError **)error {
    double value;
    
    if (![self evaluate:NULL floatvalue:&value integer:0 error:error]) {
        return NO;
    }

    idToken token;
    idToken_Init(&token);
    token.whiteSpaceStart_p = NULL;
    token.whiteSpaceEnd_p = NULL;
    token.line = [self->scriptstack lineNum];
    token.linesCrossed = 0;
    token.flags = 0;
    idToken_AssignFromFloat(&token, value);
    [self unreadSourceToken:&token];
    if (value < 0) {
        [self unreadSignToken];
    }
    return YES;
}

-(BOOL)readDirective:(NSError **)error {
    idToken token;
    
    idToken_Init(&token);

    //read the directive name
    if (![self readSourceToken:&token error:error]) {
        [self error:error format:@"found '#' without name"];
        return NO;
    }
    //directive name must be on the same line
    if (token.linesCrossed > 0) {
        [self unreadSourceToken:&token];
        [self error:error format:@"found '#' at end of line"];
        return NO;
    }
    //if if is a name
    if (token.type == TT_NAME) {
        if (!strcmp(token.text, "if")) {
            return [self directive_if:error];
        } else if (!strcmp(token.text, "ifdef")) {
            return [self directive_ifdef:error];
        }
        else if (!strcmp(token.text, "ifndef")) {
            return [self directive_ifndef:error];
        }
        else if (!strcmp(token.text, "elif")) {
            return [self directive_elif:error];
        }
        else if (!strcmp(token.text, "else")) {
            return [self directive_else:error];
        }
        else if (!strcmp(token.text, "endif")) {
            return [self directive_endif:error];
        }
        else if (self->skip > 0) {
            // skip the rest of the line
            while ([self readLine:&token error:error]) {
            }
            return YES;
        }
        else {
            if (!strcmp(token.text, "include")) {
                return [self directive_include:error];
            }
            else if (!strcmp(token.text, "define")) {
                return [self directive_define:error];
            }
            else if (!strcmp(token.text, "undef")) {
                return [self directive_undef:error];
            }
            else if (!strcmp(token.text, "line")) {
                return [self directive_line:error];
            }
            else if (!strcmp(token.text, "error")) {
                return [self directive_error:error];
            }
            else if (!strcmp(token.text, "warning")) {
                return [self directive_warning:error];
            }
            else if (!strcmp(token.text, "pragma")) {
                return [self directive_pragma:error];
            }
            else if (!strcmp(token.text, "eval")) {
                return [self directive_eval:error];
            }
            else if (!strcmp(token.text, "evalfloat")) {
                return [self directive_evalfloat:error];
            }
        }
    }
    [self error:error format:@"unknown precompiler directive '%s'", token.text];
    return NO;
}

-(BOOL)dollarDirective_evalint:(NSError **)error {
    signed long int value;
    idToken token;

    if (![self dollarEvaluate:&value floatvalue:NULL integer:1 error:error]) {
        return NO;
    }

    idToken_Init(&token);
    token.whiteSpaceStart_p = NULL;
    token.whiteSpaceEnd_p = NULL;
    token.line = [self->scriptstack lineNum];
    token.linesCrossed = 0;
    token.flags = 0;
    idToken_AssignFromInt(&token, value);
    [self unreadSourceToken:&token];
    if ( value < 0 ) {
        [self unreadSignToken];
    }
    return YES;
}

-(BOOL)dollarDirective_evalfloat:(NSError **)error {
    double value;
    idToken token;

    if (![self dollarEvaluate:NULL floatvalue:&value integer:0 error:error]) {
        return NO;
    }
    
    idToken_Init(&token);
    token.whiteSpaceStart_p = NULL;
    token.whiteSpaceEnd_p = NULL;
    token.line = [self->scriptstack lineNum];
    token.linesCrossed = 0;
    token.flags = 0;
    idToken_AssignFromFloat(&token, value);

    [self unreadSourceToken:&token];
    if (value < 0) {
        [self unreadSignToken];
    }
    return YES;
}

-(BOOL)readDollarDirective:(NSError **)error {
    idToken token;
    
    idToken_Init(&token);

    // read the directive name
    if (![self readSourceToken:&token error:error]) {
        [self error:error format:@"found '$' without name"];
        return NO;
    }
    // directive name must be on the same line
    if (token.linesCrossed > 0 ) {
        [self unreadSourceToken:&token];
        [self error:error format:@"found '$' at end of line"];
        return NO;
    }
    // if if is a name
    if (token.type == TT_NAME) {
        if (!strcmp(token.text, "evalint")) {
            return [self dollarDirective_evalint:error];
        } else if (!strcmp(token.text, "evalfloat")) {
            return [self dollarDirective_evalfloat:error];
        }
    }
    [self unreadSourceToken:&token];
    return NO;
}

-(BOOL)readToken:(idToken *)token error:(NSError **)error {
    define_t *define;

    while (1) {
        if (![self readSourceToken:token error:error]) {
            return NO;
        }
        // check for precompiler directives
        if (token->type == TT_PUNCTUATION && token->text[0] == '#' && token->text[1] == '\0') {
            // read the precompiler directive
            if (![self readDirective:error]) {
                return NO;
            }
            continue;
        }
        // if skipping source because of conditional compilation
        if (self->skip) {
            continue;
        }
        // recursively concatenate strings that are behind each other still resolving defines
        if (token->type == TT_STRING && !([self->scriptstack flags] & LEXFL_NOSTRINGCONCAT)) {
            idToken newtoken;

            idToken_Init(&newtoken);
            if ([self readToken:&newtoken error:error]) {
                if (newtoken.type == TT_STRING) {
                    idToken_AppendToken(token, &newtoken);
                } else {
                    [self unreadSourceToken:&newtoken];
                }
            }
        }
        //
        if (!([self->scriptstack flags]& LEXFL_NODOLLARPRECOMPILE)) {
            // check for special precompiler directives
            if (token->type == TT_PUNCTUATION && token->text[0] == '$' && token->text[1] == '\0') {
                // read the precompiler directive
                if ([self readDollarDirective:error]) {
                    continue;
                }
            }
        }
        // if the token is a name
        if (token->type == TT_NAME && !(token->flags & TOKEN_FL_RECURSIVE_DEFINE)) {
            // check if the name is a define macro
            define = findHashedDefine(self->definehash, token->text);
            // if it is a define macro
            if (define) {
                // expand the defined macro
                if (![self expandDefine:define intoSource:token error:error]) {
                    return NO;
                }
                continue;
            }
        }
        // found a token
        return YES;
    }
}

-(BOOL)expectTokenString:(NSString *)string error:(NSError **)error {
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

-(BOOL)expectTokenType:(int)type subtype:(int)subtype token:(idToken *)token error:(NSError **)error {
    NSString *str;

    if (![self readToken:token error:error]) {
        [self error:error format:@"couldn't read expected token"];
        return NO;
    }

    if (token->type != type) {
        switch (type) {
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
        if ((token->subtype & subtype) != subtype) {
            str = @"";
            
            if (subtype & TT_DECIMAL) str = @"decimal ";
            if (subtype & TT_HEX) str = @"hex ";
            if (subtype & TT_OCTAL) str = @"octal ";
            if (subtype & TT_BINARY) str = @"binary ";
            if (subtype & TT_UNSIGNED) str = [str stringByAppendingString:@"unsigned "];
            if (subtype & TT_LONG) str = [str stringByAppendingString:@"long "];
            if (subtype & TT_FLOAT) str = [str stringByAppendingString:@"float "];
            if (subtype & TT_INTEGER) str = [str stringByAppendingString:@"integer "];
            NSMutableString *tmpStr = [str mutableCopy];
            [tmpStr stripTrailingChar:' '];
            str = tmpStr;
            
            [self error:error format:@"expected %@ but found %s", str, token->text];
            return NO;
        }
    } else if (token->type == TT_PUNCTUATION) {
        if (subtype < 0) {
            [self error:error format:@"BUG: wrong punctuation subtype"];
            return NO;
        }
        if (token->subtype != subtype) {
            [self error:error format:@"expected '%@' but found '%s'", [self->scriptstack punctuationFromId:subtype], token->text];
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
    //if the token is available
    if (!strcmp(tok.text, [string UTF8String])) {
        return YES;
    }
    //
    [self unreadSourceToken:&tok];
    return NO;
}

-(BOOL)checkTokenType:(int)type subtype:(int)subtype token:(idToken *)token error:(NSError **)error {
    idToken tok;

    idToken_Init(&tok);
    if (![self readToken:&tok error:error]) {
        return NO;
    }
    //if the type matches
    if (tok.type == type && (tok.subtype & subtype) == subtype) {
        idToken_AssignFromToken(token, &tok);
        return YES;
    }
    //
    [self unreadSourceToken:&tok];
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
            [self unreadSourceToken:&token];
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
        if (token.type == TT_PUNCTUATION) {
            if (!strcmp(token.text, "{")) {
                depth++;
            } else if (!strcmp(token.text, "}")) {
                depth--;
            }
        }
    } while (depth);
    return YES;
}

-(BOOL)parseBracedSectionExact:(NSMutableString *)str tabs:(int)tabs error:(NSError **)error {
    return [self->scriptstack parseBracedSectionExact:str tabs:tabs error:error];
}

-(BOOL)parseBracedSection:(NSMutableString *)str tabs:(int)tabs error:(NSError **)error {
    idToken token;
    int i, depth;
    BOOL doTabs = NO;
    if (tabs >= 0) {
        doTabs = YES;
    }
    
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
        for (i = 0; i < token.linesCrossed; i++) {
            [str appendString:@"\r\n"];
        }

        if (doTabs && token.linesCrossed) {
            i = tabs;
            if (token.text[0] == '}' && i > 0) {
                i--;
            }
            while (i-- > 0) {
                [str appendString:@"\t"];
            }
        }
        if (token.type == TT_PUNCTUATION ) {
            if (token.text[0] == '{') {
                depth++;
                if (doTabs) {
                    tabs++;
                }
            } else if (token.text[0] == '}') {
                depth--;
                if (doTabs) {
                    tabs--;
                }
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
    while ([self readToken:&token error:error]) {
        if (token.linesCrossed) {
            [self unreadSourceToken:&token];
            break;
        }
        if ([str length]) {
            [str appendString:@" "];
        }
        [str appendFormat:@"%s", token.text];
    }
    return YES;
}

-(void)unreadToken:(idToken *)token {
    [self unreadSourceToken:token];
}

-(BOOL)readTokenOnLine:(idToken *)token error:(NSError **)error {
    idToken tok;
    
    idToken_Init(&tok);

    if (![self readToken:&tok error:error]) {
        return NO;
    }
    // if no lines were crossed before this token
    if (tok.linesCrossed) {
        idToken_AssignFromToken(token, &tok);
        return YES;
    }
    //
    [self unreadSourceToken:&tok];
    return NO;
}

-(BOOL)parseInt:(int *)result error:(NSError **)error {
    idToken token;
    
    idToken_Init(&token);

    if (![self readToken:&token error:error]) {
        [self error:error format:@"couldn't read expected integer"];
        return NO;
    }
    if (token.type == TT_PUNCTUATION && !strcmp(token.text, "-")) {
        [self expectTokenType:TT_NUMBER subtype:TT_INTEGER token:&token error:error];
        if (result)
            *result = -((signed int)idToken_IntValue(&token));
        return YES;
    } else if (token.type != TT_NUMBER || token.subtype == TT_FLOAT) {
        [self error:error format:@"expected integer value, found '%s'", token.text];
    }
    if (result)
        *result = idToken_IntValue(&token);
    return YES;
}

-(BOOL)parseBool:(BOOL *)result error:(NSError **)error {
    idToken token;
    
    idToken_Init(&token);

    if (![self expectTokenType:TT_NUMBER subtype:0 token:&token error:error]) {
        [self error:error format:@"couldn't read expected boolean"];
        return NO;
    }
    if (result)
        *result = (idToken_IntValue(&token) != 0);
    return YES;
}

-(BOOL)parseFloat:(float *)result error:(NSError **)error {
    idToken token;

    idToken_Init(&token);

    if (![self readToken:&token error:error]) {
        [self error:error format:@"couldn't read expected floating point number"];
        if (result) *result = 0.0f;
        return NO;
    }
    if (token.type == TT_PUNCTUATION && !strcmp(token.text, "-")) {
        [self expectTokenType:TT_NUMBER subtype:0 token:&token error:error];
        if (result) *result = -idToken_FloatValue(&token);
        return YES;
    }
    else if (token.type != TT_NUMBER) {
        [self error:error format:@"expected float value, found '%s'", token.type];
    }
    if (result) *result = idToken_FloatValue(&token);
    return YES;
}

-(BOOL)parse1DMatrix:(int)x matrix:(float *)m isRavenMatrix:(BOOL)ravenMatrix error:(NSError **)error {
    int i;

    if (!ravenMatrix)
    {
        if (![self expectTokenString:@"(" error:error]) {
            return NO;
        }
    }

    for (i = 0; i < x; i++) {
        if (![self parseFloat:&m[i] error:error]) {
            return NO;
        }

        if (ravenMatrix && i < x - 1) {
            if (![self expectTokenString:@"," error:error]) {
                return NO;
            }
        }
    }

    if (!ravenMatrix)
    {
        if (![self expectTokenString:@")" error:error]) {
            return NO;
        }
    }
    return YES;
}

-(BOOL)parse2DMatrix:(int)y x:(int)x matrix:(float *)m error:(NSError **)error {
    int i;

    if (![self expectTokenString:@"(" error:error]) {
        return NO;
    }

    for (i = 0; i < y; i++) {
        if (![self parse1DMatrix:x matrix:m + i * x isRavenMatrix:NO error:error]) {
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

-(int)lastWhiteSpace:(NSMutableString *)whiteSpace {
    if (self->scriptstack) {
        [scriptstack lastWhiteSpace:whiteSpace];
    } else {
        [whiteSpace setString:@""];
    }
    return( int)[whiteSpace length];
}

-(void)setMarker {
    marker_p = NULL;
}

-(void)stringFromMarker:(NSMutableString *)str clean:(BOOL)clean error:(NSError **)error {
    char*    p;
    char    save;

    if (self->marker_p == NULL) {
        self->marker_p = [self->scriptstack buffer];
    }
        
    if (self->tokens) {
        p = (char*)self->tokens->whiteSpaceStart_p;
    } else {
        p = (char*)[self->scriptstack scriptPointer];
    }
    
    // Set the end character to NULL to give us a complete string
    save = *p;
    *p = 0;
    
    // If cleaning then reparse
    if (clean) {
        idParser *temp = [[idParser alloc] initWithBuffer:marker_p length:strlen(marker_p) name:@"temp" flags:self->flags error:error];
        idToken token;
        
        idToken_Init(&token);

        while ([temp readToken:&token error:error]) {
            [str appendFormat:@"%s", token.text];
        }
    } else {
        [str setString:[NSString stringWithFormat:@"%s", marker_p]];
    }
    
    // restore the character we set to NULL
    *p = save;
}

-(void)setIncludePath:(NSString *)path {
    self->includepath = path;
    // add trailing path seperator
    if (![self->includepath hasSuffix:@"\\"] &&
        ![self->includepath hasSuffix:@"/"]) {
// RAVEN BEGIN
        self->includepath = [self->includepath stringByAppendingString:@"/"];
// RAVEN END
    }
}

-(void)setPunctuations:(const punctuation_t *)p {
    self->punctuations = p;
}

-(void)setFlags:(int)flags {
    idLexer *s;

    self->flags = flags;
    for (s = self->scriptstack; s; s = [s next]) {
        [s setFlags:flags];
    }
}

-(int)flags {
    return self->flags;
}

-(BOOL)loadFile:(NSString *)filename isOSPath:(BOOL)OSPath error:(NSError **)error {
    idLexer *script;

    if (self->loaded ) {
        [self error:error format:@"loadFile: another source already loaded"];
        return NO;
    }
    script = [[idLexer alloc] initWithFileName:filename flags:0 isOSPath:OSPath fileSystem:self.fileSystem error:error];
    if (!script.isLoaded) {
        script = nil; //delete script;
        return NO;
    }
    [script setFlags:self->flags];
    [script setPunctuations:self->punctuations];
    [script setNext:nil];
    self->OSPath = OSPath;
    self->filename = filename;
    self->scriptstack = script;
    self->tokens = nil;
    self->indentstack = nil;
    self->skip = 0;
    self->loaded = YES;

    if (!self->definehash) {
        self->defines = NULL;
//RAVEN BEGIN
//amccarthy: Added memory allocation tag
        self->definehash = (define_t **) calloc(1, DEFINEHASHSIZE * sizeof(define_t *));
//RAVEN END
        [self addGlobalDefinesToSource];
    }
    return YES;
}

-(BOOL)loadMemory:(const char *)ptr length:(int)length name:(NSString *)name error:(NSError **)error {
    idLexer *script;

    if (self->loaded) {
        [self error:error format:@"loadMemory: another source already loaded"];
        return NO;
    }
    script = [[idLexer alloc] initWithBuffer:ptr length:length name:name flags:0 fileSystem:self.fileSystem error:error];
    if (![script isLoaded]) {
        script = nil; // delete script;
        return NO;
    }
    [script setFlags:self->flags];
    [script setPunctuations:self->punctuations];
    //[script setNext:nil];
    self->filename = name;
    self->scriptstack = script;
    self->tokens = nil;
    self->indentstack = nil;
    self->skip = 0;
    self->loaded = YES;

    if (!self->definehash) {
        self->defines = NULL;
//RAVEN BEGIN
//amccarthy: Added memory allocation tag
        self->definehash = (define_t **)calloc(DEFINEHASHSIZE * sizeof(define_t *), 1);
//RAVEN END
        [self addGlobalDefinesToSource];
    }
    return YES;
}

-(void)freeSource:(bool)keepDefines {
    idLexer *script;
    idToken *token;
    define_t *define;
    indent_t *indent;
    int i;

    // free all the scripts
    while (self->scriptstack) {
        script = self->scriptstack;
        self->scriptstack = [self->scriptstack next];
        script = nil; // delete script;
    }
    // free all the tokens
    while (self->tokens) {
        token = self->tokens;
        self->tokens = tokens->next;
        token = nil; // delete token;
    }
    // free all indents
    while (self->indentstack) {
        indent = self->indentstack;
        self->indentstack = self->indentstack->next;
        free(indent);
    }
    if (!keepDefines) {
        // free hash table
        if (self->definehash) {
            // free defines
            for (i = 0; i < DEFINEHASHSIZE; i++) {
                while (self->definehash[i]) {
                    define = self->definehash[i];
                    self->definehash[i] = self->definehash[i]->hashnext;
                    freeDefine(define);
                }
            }
            self->defines = NULL;
            free(self->definehash);
            self->definehash = NULL;
        }
    }
    self->loaded = NO;
}

-(const char *)punctuationFromId:(int)ident {
    int i;

    if (!self->punctuations) {
        idLexer *lex = [[idLexer alloc] initWithFileSystem:self.fileSystem];
        return [lex punctuationFromId:ident];
    }

    for (i = 0; self->punctuations[i].p; i++) {
        if (self->punctuations[i].n == ident) {
            return self->punctuations[i].p;
        }
    }
    return "unknown punctuation";
}

-(int)punctuationId:(NSString *)p {
    int i;

    if (!self->punctuations) {
        idLexer *lex = [[idLexer alloc] initWithFileSystem:self.fileSystem];
        return [lex punctuationId:[p UTF8String]];
    }

    for (i = 0; self->punctuations[i].p; i++) {
        if (!strcmp(self->punctuations[i].p, [p UTF8String])) {
            return self->punctuations[i].n;
        }
    }
    return 0;
}

-(instancetype)initWithFileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->loaded = NO;
        self->OSPath = NO;
        self->punctuations = 0;
        self->flags = 0;
        self->scriptstack = NULL;
        self->indentstack = NULL;
        self->definehash = NULL;
        self->defines = NULL;
        self->tokens = NULL;
        self->marker_p = NULL;
        
        // RAVEN BEGIN
        // bdube: added members
        marker_p = NULL;
        // RAVEN END
        
        self.fileSystem = fileSystem;
    }
    return self;
}

-(instancetype)initWithFlags:(int)flags fileSystem:(idFileSystem *)fileSystem {
    self = [super init];
    if (self) {
        self->loaded = NO;
        self->OSPath = NO;
        self->punctuations = 0;
        self->flags = flags;
        self->scriptstack = NULL;
        self->indentstack = NULL;
        self->definehash = NULL;
        self->defines = NULL;
        self->tokens = NULL;
        self->marker_p = NULL;
        
        // RAVEN BEGIN
        // bdube: added members
        marker_p = NULL;
        // RAVEN END
        
        self.fileSystem = fileSystem;
    }
    return self;
}


- (instancetype)initWithFileName:(NSString *)filename
                           flags:(int)flags
                        isOSPath:(BOOL)OSPath
                      fileSystem:(idFileSystem *)fileSystem
                           error:(NSError **)error {
    self = [super init];
    if (self) {
        self->loaded = NO;
        self->OSPath = OSPath;
        self->punctuations = 0;
        self->flags = flags;
        self->scriptstack = NULL;
        self->indentstack = NULL;
        self->definehash = NULL;
        self->defines = NULL;
        self->tokens = NULL;
        self->marker_p = NULL;
        
        self.fileSystem = fileSystem;
        
        [self loadFile:filename isOSPath:OSPath error:error];
    }
    return self;
}

- (instancetype)initWithBuffer:(const char *)ptr length:(int)length name:(NSString *)name flags:(int)flags error:(NSError **)error {
    self = [super init];
    if (self) {
        self->loaded = NO;
        self->OSPath = NO;
        self->punctuations = 0;
        self->flags = flags;
        self->scriptstack = NULL;
        self->indentstack = NULL;
        self->definehash = NULL;
        self->defines = NULL;
        self->tokens = NULL;
        self->marker_p = NULL;
        if (![self loadMemory:ptr length:length name:name error:error]) {
            return nil;
        }
    }
    return self;
}

-(void)dealloc {
    [self freeSource:NO];
}

-(BOOL)parse1DMatrixLegacy:(int)x matrix:(float*)m error:(NSError **)error {
    int i;

    if (![self expectTokenString:@"{" error:error])
    {
        return NO;
    }

    for (i = 0; i < x; i++)
    {
        if (![self parseFloat:&m[i] error:error]) {
            return NO;
        }

        if (i < x - 1)
        {
            if (![self expectTokenString:@"," error:error])
            {
                return NO;
            }
        }
    }

    if (![self expectTokenString:@"}" error:error])
    {
        return NO;
    }
    return YES;
}
// jmarshall end

@end
