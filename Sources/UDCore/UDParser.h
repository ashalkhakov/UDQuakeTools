//
//  UDParser.h
//  PakManager
//
//  Created by artyom on 7/10/26.
//

#import <Foundation/Foundation.h>
#import "UDToken.h"
#import "UDLexer.h"

@interface UDIdParser : NSObject

- (instancetype)initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (UDIdToken *)peekToken;
- (UDIdToken *)readToken;
- (void)unreadToken:(UDIdToken *)token;
- (BOOL)readToken:(UDIdToken * _Nullable * _Nonnull)outToken;
- (BOOL)expectTokenType:(UDIdTokenKind)kind token:(UDIdToken * _Nullable * _Nonnull)outToken;
- (BOOL)expectTokenString:(NSString *)tokenString token:(UDIdToken * _Nullable * _Nonnull)outToken;
- (BOOL)expectPunctuation:(NSString *)punctuation;
- (void)skipUntilPunctuation:(NSString *)punctuation;
- (void)setMarker;
- (NSString *)getStringFromMarkerTrimLeadingWhitespace:(BOOL)trimLeadingWhitespace;
- (BOOL)parseBracedSectionExact:(NSString * _Nonnull * _Nonnull)outSection startingWithOpenBraceToken:(nullable UDIdToken *)openBraceToken;

@end


/*
===============================================================================

    C/C++ compatible pre-compiler

===============================================================================
*/

#define DEFINE_FIXED            0x0001

#define BUILTIN_LINE            1
#define BUILTIN_FILE            2
#define BUILTIN_DATE            3
#define BUILTIN_TIME            4
#define BUILTIN_STDC            5

#define INDENT_IF                0x0001
#define INDENT_ELSE                0x0002
#define INDENT_ELIF                0x0004
#define INDENT_IFDEF            0x0008
#define INDENT_IFNDEF            0x0010

// macro definitions
typedef struct define_s {
    char *            name;                        // define name
    int                flags;                        // define flags
    int                builtin;                    // > 0 if builtin define
    int                numparms;                    // number of define parameters
    idToken *        parms;                        // define parameters
    idToken *        tokens;                        // macro tokens (possibly containing parm tokens)
    struct define_s    *next;                        // next defined macro in a list
    struct define_s    *hashnext;                    // next define in the hash chain
} define_t;

// indents used for conditional compilation directives:
// #if, #else, #elif, #ifdef, #ifndef
typedef struct indent_s {
    int                type;                        // indent type
    int                skip;                        // true if skipping current indent
    idLexer *        script;                        // script the indent was in
    struct indent_s    *next;                        // next indent on the indent stack
} indent_t;

@interface idParser : NSObject {
    int                  loaded;                        // set when a source file is loaded from file or memory
    NSString *           filename;                    // file name of the script
    NSString *           includepath;                // path to include files
    BOOL                 OSPath;                        // true if the file was loaded from an OS path
    const punctuation_t *punctuations;            // punctuations to use
    int                  flags;                        // flags used for script parsing
    idLexer *            scriptstack;                // stack with scripts of the source
    idToken *            tokens;                        // tokens to read first
    define_t *           defines;                    // list with macro definitions
    define_t **          definehash;                    // hash chain with defines
    indent_t *           indentstack;                // stack with indents
    int                  skip;                        // > 0 if skipping conditional code
    idToken *            token;                        // last read token
    const char*          marker_p;
}

- (instancetype)init;
- (instancetype)initWithFlags:(int)flags;
- (instancetype)initWithFileName:(NSString *)filename flags:(int)flags isOSPath:(BOOL)OSPath;
- (instancetype)initWithBuffer:(const char *)ptr length:(int)length name:(NSString *)name flags:(int)flags error:(NSError **)error;

// load a source file
- (BOOL)loadFile:(NSString *)filename isOSPath:(BOOL)OSPath error:(NSError **)error;
// load a source from memory
- (BOOL)loadMemory:(const char *)ptr length:(int)length name:(NSString *)name startLine:(int)startLine error:(NSError**)error;
// free the current source
- (void)freeSource:(BOOL)keepDefines;
// returns true if a source is loaded
- (BOOL)isLoaded;
// read a token from the source
- (BOOL)readToken:(idToken *)token error:(NSError **)error;
// expect a certain token, reads the token when available
- (BOOL)expectTokenString:(NSString *)string error:(NSError **)error;
// expect a certain token type
- (BOOL)expectTokenType:(int)type subtype:(int)subtype into:(idToken *)token error:(NSError **)error;
// expect a token
- (BOOL)expectAnyToken:(idToken *)token error:(NSError **)error;
// returns true and reads the token when it is available
- (BOOL)checkTokenString:(NSString *)string error:(NSError **)error;
// returns true and reads the token when a token with the given type is available
- (BOOL)checkTokenType:(int)type subtype:(int)subtype into:(idToken *)token error:(NSError **)error;
// skip tokens until the given token string is read
- (BOOL)skipUntilString:(NSString *)string error:(NSString **)error;
// skip the rest of the current line
-(BOOL)skipRestOfLine:(NSError **)error;
// jmarshall
-(BOOL)parse1DMatrixLegacy:(int)x matrix:(float*)m error:(NSError **)error;
// jmarshall end
// skip the braced section
-(BOOL)skipBracedSection:(BOOL)parseFirstBrace error:(NSError **)error;
// parse a braced section into a string
-(BOOL)parseBracedSection:(NSMutableString *)str tabs:(int)tabs error:(NSError **)error;
// parse a braced section into a string, maintaining indents and newlines
-(BOOL)parseBracedSectionExact:(NSMutableString *)str tabs:(int)tabs error:(NSError **)error;
// parse the rest of the line
-(BOOL)parseRestOfLine:(NSMutableString *)str error:(NSError **)error;
// unread the given token
-(BOOL)unreadToken:(idToken *)token error:(NSError **)error;
// read a token only if on the current line
-(BOOL)readTokenOnLine:(idToken *)token error:(NSError **)error;
// read a signed integer
-(BOOL)parseInt:(int *)result error:(NSError **)error;
// read a boolean
-(BOOL)parseBool:(BOOL *)result error:(NSError **)error;
// read a floating point number
-(BOOL)parseFloat:(float *)result error:(NSError **)error;
// parse matrices with floats
-(BOOL)parse1DMatrix:(int)x matrix:(float *)m isRavenMatrix:(BOOL)ravenMatrix error:(NSError **)error;
-(BOOL)parse2DMatrix:(int)y x:(int)x matrix:(float *)m error:(NSError **)error;
-(BOOL)parse3DMatrix:(int)z y:(int)y x:(int)x matrix:(float *)m error:(NSError **)error;
// get the white space before the last read token
-(int)lastWhiteSpace:(NSMutableString *)whiteSpace;
// Set a marker in the source file (there is only one marker)
-(void)setMarker;
// Get the string from the marker to the current position
-(void)stringFromMarker:(NSMutableString *)str clean:(BOOL)clean error:(NSError **)error;
// add a define to the source
-(BOOL)addDefine:(NSString *)string error:(NSError **)error;
// add builtin defines
-(void)addBuiltinDefines;
// set the source include path
-(void)setIncludePath:(NSString *)path;
// set the punctuation set
-(void)setPunctuations:(const punctuation_t *)p;
// returns a pointer to the punctuation with the given id
-(const char *)punctuationFromId:(int)ident;
// get the id for the given punctuation
-(int)punctuationId:(NSString *)p;
// set lexer flags
-(void)setFlags:(int)flags;
// get lexer flags
-(int)flags;
// returns the current filename
-(NSString *)fileName;
// get current offset in current script
-(int)fileOffset;
// get file time for current script
-(unsigned int)fileTime;
// returns the current line number
-(int)lineNum;
// print an error message
- (void)error:(NSError **)error format:(NSString *)format, ...;
// print a warning message
- (void)warning:(NSString *)format, ...;

// add a global define that will be added to all opened sources
+ (BOOL)addGlobalDefine:(NSString *)string;
// remove the given global define
+ (BOOL)removeGlobalDefine:(NSString *)name;
// remove all global defines
+ (void)removeAllGlobalDefines;
// set the base folder to load files from
+ (void)setBaseFolder:(NSString *)path;
@end
