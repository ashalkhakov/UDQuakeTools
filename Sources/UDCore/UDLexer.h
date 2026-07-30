//
//  UDLexer.h
//  PakManager
//
//  Created by artyom on 7/10/26.
//

#import <Foundation/Foundation.h>
#import "UDToken.h"

@interface UDIdLexer : NSObject

- (instancetype)initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (UDIdToken *)nextToken;

@end

/*
===============================================================================

    Lexicographical parser

    Does not use memory allocation during parsing. The lexer uses no
    memory allocation if a source is loaded with LoadMemory().
    However, idToken may still allocate memory for large strings.
    
    A number directly following the escape character '\' in a string is
    assumed to be in decimal format instead of octal. Binary numbers of
    the form 0b.. or 0B.. can also be used.

===============================================================================
*/

#ifndef BIT
#define BIT(n) (1U << (n))
#endif

// lexer flags
typedef enum {
    LEXFL_NOERRORS                        = BIT(0),    // don't print any errors
    LEXFL_NOWARNINGS                    = BIT(1),    // don't print any warnings
    LEXFL_NOFATALERRORS                    = BIT(2),    // errors aren't fatal
    LEXFL_NOSTRINGCONCAT                = BIT(3),    // multiple strings seperated by whitespaces are not concatenated
    LEXFL_NOSTRINGESCAPECHARS            = BIT(4),    // no escape characters inside strings
    LEXFL_NODOLLARPRECOMPILE            = BIT(5),    // don't use the $ sign for precompilation
    LEXFL_NOBASEINCLUDES                = BIT(6),    // don't include files embraced with < >
    LEXFL_ALLOWPATHNAMES                = BIT(7),    // allow path seperators in names
    LEXFL_ALLOWNUMBERNAMES                = BIT(8),    // allow names to start with a number
    LEXFL_ALLOWIPADDRESSES                = BIT(9),    // allow ip addresses to be parsed as numbers
    LEXFL_ALLOWFLOATEXCEPTIONS            = BIT(10),    // allow float exceptions like 1.#INF or 1.#IND to be parsed
    LEXFL_ALLOWMULTICHARLITERALS        = BIT(11),    // allow multi character literals
    LEXFL_ALLOWBACKSLASHSTRINGCONCAT    = BIT(12),    // allow multiple strings seperated by '\' to be concatenated
    LEXFL_ONLYSTRINGS                    = BIT(13),    // parse as whitespace deliminated strings (quoted strings keep quotes)
// RAVEN BEGIN
// jsinger: added to support binary writing from the lexer in either byte swapped or non-byte swapped formats
    LEXFL_READBINARY                    = BIT(29),    // read a byte code compiled version of the file
    LEXFL_BYTESWAP                        = BIT(30),    // when writing the byte code compiled file, byte swap numbers
    LEXFL_WRITEBINARY                    = BIT(31)    // write out a byte code compiled version of the file
// RAVEN END
} lexerFlags_t;

// punctuation ids
#define P_RSHIFT_ASSIGN                1
#define P_LSHIFT_ASSIGN                2
#define P_PARMS                        3
#define P_PRECOMPMERGE                4

#define P_LOGIC_AND                    5
#define P_LOGIC_OR                    6
#define P_LOGIC_GEQ                    7
#define P_LOGIC_LEQ                    8
#define P_LOGIC_EQ                    9
#define P_LOGIC_UNEQ                10

#define P_MUL_ASSIGN                11
#define P_DIV_ASSIGN                12
#define P_MOD_ASSIGN                13
#define P_ADD_ASSIGN                14
#define P_SUB_ASSIGN                15
#define P_INC                        16
#define P_DEC                        17

#define P_BIN_AND_ASSIGN            18
#define P_BIN_OR_ASSIGN                19
#define P_BIN_XOR_ASSIGN            20
#define P_RSHIFT                    21
#define P_LSHIFT                    22

#define P_POINTERREF                23
#define P_CPP1                        24
#define P_CPP2                        25
#define P_MUL                        26
#define P_DIV                        27
#define P_MOD                        28
#define P_ADD                        29
#define P_SUB                        30
#define P_ASSIGN                    31

#define P_BIN_AND                    32
#define P_BIN_OR                    33
#define P_BIN_XOR                    34
#define P_BIN_NOT                    35

#define P_LOGIC_NOT                    36
#define P_LOGIC_GREATER                37
#define P_LOGIC_LESS                38

#define P_REF                        39
#define P_COMMA                        40
#define P_SEMICOLON                    41
#define P_COLON                        42
#define P_QUESTIONMARK                43

#define P_PARENTHESESOPEN            44
#define P_PARENTHESESCLOSE            45
#define P_BRACEOPEN                    46
#define P_BRACECLOSE                47
#define P_SQBRACKETOPEN                48
#define P_SQBRACKETCLOSE            49
#define P_BACKSLASH                    50

#define P_PRECOMP                    51
#define P_DOLLAR                    52

// RAVEN BEGIN
#define P_INVERTED_PLING            53
#define P_INVERTED_QUERY            54
// RAVEN END

// punctuation
typedef struct punctuation_s
{
    const char *p;                    // punctuation character(s)
    int n;                            // punctuation id
} punctuation_t;

@class idFileSystem;

@interface idLexer : NSObject {
    int                loaded;                    // set when a script file is loaded from file or memory
    NSString*          filename;                  // file name of the script
    bool               allocated;                 // true if buffer memory was allocated
    const char *       buffer;                    // buffer containing the script
    const char *       script_p;                  // current pointer in the script
    const char *       end_p;                     // pointer to the end of the script
    const char *       lastScript_p;              // script pointer before reading token
    const char *       whiteSpaceStart_p;         // start of last white space
    const char *       whiteSpaceEnd_p;           // end of last white space
    unsigned int       fileTime;                  // file time
    int                length;                    // length of the script in bytes
    int                line;                      // current line in script
    int                lastline;                  // line before reading token
    int                tokenavailable;            // set by unreadToken
    int                flags;                     // several script flags
    const punctuation_t *punctuations;            // the punctuations used in the script
    int *              punctuationtable;          // ASCII table with punctuations
    int *              nextpunctuation;           // next punctuation in chain
    idToken            token;                     // available token
    idLexer *          next;                      // next script in a chain
    bool               hadError;                  // set by idLexer::Error, even if the error is supressed
}

@property (weak, nonatomic) idFileSystem *fileSystem;

// constructor
- (instancetype)initWithFileSystem:(idFileSystem *)fileSystem;
- (instancetype)initWithFlags:(int)flags fileSystem:(idFileSystem *)fileSystem;
- (instancetype)initWithFileName:(NSString *)filename flags:(int)flags isOSPath:(BOOL)isOSPath fileSystem:(idFileSystem *)fileSystem error:(NSError **)error;
- (instancetype)initWithBuffer:(const char *)ptr
                        length:(int)length
                          name:(NSString *)name
                         flags:(int)flags
                    fileSystem:(idFileSystem *)fileSystem
                         error:(NSError **)error;

// load a script from the given file at the given offset with the given length
- (BOOL)loadFile:(NSString *)filename isOSPath:(BOOL)isOSPath error:(NSError **)error;
// load a script from the given memory with the given length and a specified line offset,
// so source strings extracted from a file can still refer to proper line numbers in the file
// NOTE: the buffer is expect to be a valid C string: ptr[length] == '\0'
- (BOOL)loadMemory:(const char *)ptr length:(int)length name:(NSString *)name startLine:(int)startLine error:(NSError **)error;
// free the script
- (void)freeSource;
// returns true if a script is loaded
- (BOOL)isLoaded;
// read a token
- (BOOL)readToken:(idToken *)token error:(NSError **)error;
// expect a certain token, reads the token when available
- (BOOL)expectTokenString:(NSString *)string error:(NSError **)error;
// expect a certain token type
- (BOOL)expectTokenType:(int)type subtype:(int)subtype into:(idToken *)token error:(NSError **)error;
// expect a token
- (BOOL)expectAnyToken:(idToken *)token error:(NSError **)error;
// returns true when the token is available
- (BOOL)checkTokenString:(NSString *)string error:(NSError **)error;
// returns true an reads the token when a token with the given type is available
- (BOOL)checkTokenType:(int)type subtype:(int)subtype into:(idToken *)token error:(NSError **)error;
// returns true if the next token equals the given string but does not remove the token from the source
- (BOOL)peekTokenString:(NSString *)string error:(NSError **)error;
// skip tokens until the given token string is read
- (BOOL)skipUntilString:(NSString *)string error:(NSError **)error;
// skip the rest of the current line
- (BOOL)skipRestOfLine:(NSError **)error;
// skip the braced section
- (BOOL)skipBracedSection:(BOOL)parseFirstBrace error:(NSError **)error;
// unread the given token
- (BOOL)unreadToken:(idToken *)token error:(NSError **)error;
// read a token only if on the same line
- (BOOL)readTokenOnLine:(idToken *)token error:(NSError **)error;
//Returns the rest of the current line
- (void)readRestOfLine:(NSMutableString *)str;
// read a signed integer
- (BOOL)parseInt:(int *)result error:(NSError **)error;
// read a boolean
- (BOOL)parseBool:(BOOL *)result error:(NSError **)error;
// read a floating point number.  If errorFlag is NULL, a non-numeric token will
// issue an Error().  If it isn't NULL, it will issue a Warning() and set *errorFlag = true
- (BOOL)parseFloat:(float *)result error:(NSError **)error;
// parse matrices with floats
- (BOOL)parse1DMatrix:(int)x matrix:(float *)m error:(NSError **)error;
// RAVEN BEGIN
// rjohnson: added vertex color support to proc files.  assume a default RGBA of 0x000000ff
- (BOOL)parse1DMatrixOpenEnded:(int)maxCount parsedCount:(int *)parsedCount matrix:(float *)m error:(NSError **)error;
// RAVEN END
- (BOOL)parse2DMatrix:(int)y x:(int)y matrix:(float *)m error:(NSError **)error;
- (BOOL)parse3DMatrix:(int)z y:(int)y x:(int)x matrix:(float *)m error:(NSError **)error;
// parse a braced section into a string
- (BOOL)parseBracedSection:(NSMutableString *)str error:(NSError **)error;
// parse a braced section into a string, maintaining indents and newlines
- (BOOL)parseBracedSectionExact:(NSMutableString *)str tabs:(int)tabs error:(NSError **)error;
// parse the rest of the line
- (BOOL)parseRestOfLine:(NSMutableString *)str error:(NSError **)error;
// retrieves the white space characters before the last read token
- (int)lastWhiteSpace:(NSMutableString *)whiteSpace;
// returns start index into text buffer of last white space
- (int)lastWhiteSpaceStart;
// returns end index into text buffer of last white space
- (int)lastWhiteSpaceEnd;
// set an array with punctuations, NULL restores default C/C++ set, see default_punctuations for an example
- (void)setPunctuations:( const punctuation_t *)p;
// returns a pointer to the punctuation with the given id
- (const char *)punctuationFromId:(int)ident;
// get the id for the given punctuation
- (int)punctuationId:(const char *)p;
// set lexer flags
- (void)setFlags:(int)flags;
// get lexer flags
- (int)flags;
// reset the lexer
- (void)reset;
// returns true if at the end of the file
- (int)endOfFile;
// returns the current filename
- (NSString *)fileName;
// get offset in script
- (const int)fileOffset;
// get file time
- (const unsigned int)fileTime;
// returns the current line number
- (const int)lineNum;
// print an error message
- (BOOL)error:(NSError **)error format:(NSString *)format, ...;
// print a warning message
- (void)warning:(NSString *)format, ...;
// returns true if Error() was called with LEXFL_NOFATALERRORS or LEXFL_NOERRORS set
- (BOOL)hadError;

+ (void)setBaseFolder:(NSString *)folder;

// RAVEN BEGIN
// dluetscher: added method to parse a structure array that is made up of numerics (floats, ints), and stores them in the given storage
//void            ParseNumericStructArray( int numStructElements, int tokenSubTypeStructElements[], int arrayCount, byte *arrayStorage );
// RAVEN END

- (const char*)buffer;
- (const char*)scriptPointer;

-(idLexer *)next;                      // next script in a chain
-(void)setNext:(idLexer *)lexer;

@end
