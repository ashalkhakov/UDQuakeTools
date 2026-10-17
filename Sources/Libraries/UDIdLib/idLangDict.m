#import "idFileAccess.h"
/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idLangDict.m — see idLangDict.h.
 */

#import "idLangDict.h"
#import "idStr.h"
#import "idLexer.h"
#import "idToken.h"

@implementation idLangDict {
    // idList<idLangKeyValue> and its hash: the values by key (compared
    // with Cmp)
    NSMutableDictionary<NSString *, NSString *> *args;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        args = [NSMutableDictionary dictionary];
    }
    return self;
}

/*
============
idLangDict::Clear
============
*/
- (void)clear {
    [args removeAllObjects];
}

/*
============
idLangDict::Load
============
*/
- (BOOL)load:(NSString *)fileName clear:(BOOL)clear fileSystem:(id<idFileSystemReading>)fileSystem {

    if ( clear ) {
        [self clear];
    }

    void *buffer = NULL;
    int len = [fileSystem readFile:fileName buffer:&buffer timestamp:NULL error:NULL];
    if ( len <= 0 ) {
        // let whoever called us deal with the failure (so sys_lang can be reset)
        return NO;
    }
    idLexer *src = [[idLexer alloc] initWithFlags:LEXFL_NOFATALERRORS | LEXFL_NOSTRINGCONCAT | LEXFL_ALLOWMULTICHARLITERALS | LEXFL_ALLOWBACKSLASHSTRINGCONCAT
                                       fileSystem:fileSystem];
    [src loadMemory:buffer length:(int)strlen( buffer ) name:fileName startLine:1 error:NULL];
    if ( ![src isLoaded] ) {
        [fileSystem freeFile:buffer error:NULL];
        return NO;
    }

    idToken tok, tok2;
    idToken_Init( &tok );
    idToken_Init( &tok2 );
    [src expectTokenString:@"{" error:NULL];
    while ( [src readToken:&tok error:NULL] ) {
        if ( UDTokenIs( &tok, "}" ) ) {
            break;
        }
        if ( [src readToken:&tok2 error:NULL] ) {
            if ( UDTokenIs( &tok2, "}" ) ) {
                break;
            }
            NSString *key = UDTokenLatin1String( &tok );
            // DG: D3LE has #font_ entries in english.lang, maybe from D3BFG? not supported here, just skip them
            if ( [key ud_cmpn:@"#font_" length:6] != 0 ) {
                // args.Append: GetString finds the first of a key
                if ( args[key] == nil ) {
                    args[key] = UDTokenLatin1String( &tok2 );
                }
            }
        }
    }
    [fileSystem freeFile:buffer error:NULL];

    return YES;
}


/*
============
idLangDict::GetString
============
*/
- (NSString *)getString:(NSString *)str {

    if ( str.length == 0 ) {
        return @"";
    }

    if ( [str ud_cmpn:STRTABLE_ID length:STRTABLE_ID_LENGTH] != 0 ) {
        return str;
    }

    NSString *value = args[str];
    if ( value != nil ) {
        return value;
    }

    [self.warnings uiWarning:[NSString stringWithFormat:@"Unknown string id %@", str]];
    return str;
}

- (int)numKeyVals {
    return (int)args.count;
}

@end
