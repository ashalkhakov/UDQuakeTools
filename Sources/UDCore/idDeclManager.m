/*
===========================================================================

Doom 3 GPL Source Code
Copyright (C) 1999-2011 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 GPL Source Code (?Doom 3 Source Code?).

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

// jmarshall - Raven Decl Support
//#include "../bse/BSE_API.h"
// jmarshall end
#import "idFileSystem.h"
#import "idFile.h"
#import "idDeclManager.h"
#import "UDLexer.h"
#import "idDeclMaterial.h"
#import "idDeclParticle.h"
#import "idDeclPDA.h"
#import "idDeclTable.h"
#import "idDeclSkin.h"
#import "UDEndian.h"
#import "MD5.h"
#import "UDBitMsg.h"

@class idFile;

/*

GUIs and script remain separately parsed

Following a parse, all referenced media (and other decls) will have been touched.

sinTable and cosTable are required for the rotate material keyword to function

A new FindType on a purged decl will cause it to be reloaded, but a stale pointer to a purged
decl will look like a defaulted decl.

Moving a decl from one file to another will not be handled correctly by a reload, the material
will be defaulted.

NULL or empty decl names will always return NULL
    Should probably make a default decl for this

Decls are initially created without a textSource
A parse without textSource set should always just call MakeDefault()
A parse that has an error should internally call MakeDefault()
A purge does nothing to a defaulted decl

Should we have a "purged" media state separate from the "defaulted" media state?

reloading over a decl name that was defaulted

reloading over a decl name that was valid

missing reload over a previously explicit definition

*/

#define USE_COMPRESSED_DECLS
//#define GET_HUFFMAN_FREQUENCIES

/*
====================================================================================

 decl text huffman compression

====================================================================================
*/

const int MAX_HUFFMAN_SYMBOLS    = 256;

typedef struct huffmanNode_s {
    int                        symbol;
    int                        frequency;
    struct huffmanNode_s *    next;
    struct huffmanNode_s *    children[2];
} huffmanNode_t;

typedef struct huffmanCode_s {
    uint32_t                bits[8];
    int                        numBits;
} huffmanCode_t;

// compression ratio = 64%
static int huffmanFrequencies[] = {
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00078fb6, 0x000352a7, 0x00000002, 0x00000001, 0x0002795e, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00049600, 0x000000dd, 0x00018732, 0x0000005a, 0x00000007, 0x00000092, 0x0000000a, 0x00000919,
    0x00002dcf, 0x00002dda, 0x00004dfc, 0x0000039a, 0x000058be, 0x00002d13, 0x00014d8c, 0x00023c60,
    0x0002ddb0, 0x0000d1fc, 0x000078c4, 0x00003ec7, 0x00003113, 0x00006b59, 0x00002499, 0x0000184a,
    0x0000250b, 0x00004e38, 0x000001ca, 0x00000011, 0x00000020, 0x000023da, 0x00000012, 0x00000091,
    0x0000000b, 0x00000b14, 0x0000035d, 0x0000137e, 0x000020c9, 0x00000e11, 0x000004b4, 0x00000737,
    0x000006b8, 0x00001110, 0x000006b3, 0x000000fe, 0x00000f02, 0x00000d73, 0x000005f6, 0x00000be4,
    0x00000d86, 0x0000014d, 0x00000d89, 0x0000129b, 0x00000db3, 0x0000015a, 0x00000167, 0x00000375,
    0x00000028, 0x00000112, 0x00000018, 0x00000678, 0x0000081a, 0x00000677, 0x00000003, 0x00018112,
    0x00000001, 0x000441ee, 0x000124b0, 0x0001fa3f, 0x00026125, 0x0005a411, 0x0000e50f, 0x00011820,
    0x00010f13, 0x0002e723, 0x00003518, 0x00005738, 0x0002cc26, 0x0002a9b7, 0x0002db81, 0x0003b5fa,
    0x000185d2, 0x00001299, 0x00030773, 0x0003920d, 0x000411cd, 0x00018751, 0x00005fbd, 0x000099b0,
    0x00009242, 0x00007cf2, 0x00002809, 0x00005a1d, 0x00000001, 0x00005a1d, 0x00000001, 0x00000001,

    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000001,
};

static huffmanCode_t huffmanCodes[MAX_HUFFMAN_SYMBOLS];
static huffmanNode_t *huffmanTree = NULL;
static int totalUncompressedLength = 0;
static int totalCompressedLength = 0;
static int maxHuffmanBits = 0;


/*
================
ClearHuffmanFrequencies
================
*/
void ClearHuffmanFrequencies(void) {
    int i;

    for (i = 0; i < MAX_HUFFMAN_SYMBOLS; i++) {
        huffmanFrequencies[i] = 1;
    }
}

/*
================
InsertHuffmanNode
================
*/
huffmanNode_t *InsertHuffmanNode(huffmanNode_t *firstNode, huffmanNode_t *node) {
    huffmanNode_t *n, *lastNode;

    lastNode = NULL;
    for (n = firstNode; n; n = n->next) {
        if (node->frequency <= n->frequency) {
            break;
        }
        lastNode = n;
    }
    if (lastNode) {
        node->next = lastNode->next;
        lastNode->next = node;
    } else {
        node->next = firstNode;
        firstNode = node;
    }
    return firstNode;
}

/*
================
BuildHuffmanCode_r
================
*/
void BuildHuffmanCode_r(huffmanNode_t *node, huffmanCode_t code, huffmanCode_t codes[MAX_HUFFMAN_SYMBOLS]) {
    if (node->symbol == -1) {
        huffmanCode_t newCode = code;
        assert(code.numBits < sizeof(codes[0].bits) * 8);
        newCode.numBits++;
        if (code.numBits > maxHuffmanBits) {
            maxHuffmanBits = newCode.numBits;
        }
        BuildHuffmanCode_r(node->children[0], newCode, codes);
        newCode.bits[code.numBits >> 5] |= 1u << (code.numBits & 31);
        BuildHuffmanCode_r(node->children[1], newCode, codes);
    } else {
        assert(code.numBits <= sizeof(codes[0].bits) * 8);
        codes[node->symbol] = code;
    }
}

/*
================
FreeHuffmanTree_r
================
*/
void FreeHuffmanTree_r(huffmanNode_t *node) {
    if (node->symbol == -1) {
        FreeHuffmanTree_r(node->children[0]);
        FreeHuffmanTree_r(node->children[1]);
    }
    free(node);
 }

/*
================
HuffmanHeight_r
================
*/
int HuffmanHeight_r(huffmanNode_t *node) {
    if (node == NULL) {
        return -1;
    }
    int left = HuffmanHeight_r(node->children[0]);
    int right = HuffmanHeight_r(node->children[1]);
    if (left > right) {
        return left + 1;
    }
    return right + 1;
}

/*
================
SetupHuffman
================
*/
void SetupHuffman(void) {
    int i, height;
    huffmanNode_t *firstNode, *node;
    huffmanCode_t code;
    
    assert(sizeof(uint32_t) == 4); // Huffman storage words must be 32-bit
    
    firstNode = NULL;
    for (i = 0; i < MAX_HUFFMAN_SYMBOLS; i++) {
        node = malloc(sizeof(huffmanNode_t));
        node->symbol = i;
        node->frequency = huffmanFrequencies[i];
        node->next = NULL;
        node->children[0] = NULL;
        node->children[1] = NULL;
        firstNode = InsertHuffmanNode(firstNode, node);
    }

    for( i = 1; i < MAX_HUFFMAN_SYMBOLS; i++ ) {
        node = malloc(sizeof(huffmanNode_t));
        node->symbol = -1;
        node->frequency = firstNode->frequency + firstNode->next->frequency;
        node->next = NULL;
        node->children[0] = firstNode;
        node->children[1] = firstNode->next;
        firstNode = InsertHuffmanNode(firstNode->next->next, node);
    }

    maxHuffmanBits = 0;
    memset(&code, 0, sizeof(code));
    BuildHuffmanCode_r(firstNode, code, huffmanCodes);

    huffmanTree = firstNode;

    height = HuffmanHeight_r(firstNode);
    assert(maxHuffmanBits == height);
}

/*
================
ShutdownHuffman
================
*/
void ShutdownHuffman(void) {
    if (huffmanTree) {
        FreeHuffmanTree_r(huffmanTree);
    }
}

/*
================
HuffmanCompressText
================
*/
int HuffmanCompressText(NSMutableData *text, NSMutableData *compressed) {
    int i, j;
    UDBitMsg *msg;
    int length = (int)text.length;
    unsigned char *bytes = (unsigned char *)text.bytes;

    totalUncompressedLength += text.length;

    msg = [[UDBitMsg alloc] initWithData:compressed];
    for (i = 0; i < length; i++) {
        const huffmanCode_t *code = &huffmanCodes[bytes[i]];
        for (j = 0; j < (code->numBits >> 5); j++) {
            [msg writeBits:code->bits[j] numBits:32];
        }
        if (code->numBits & 31) {
            [msg writeBits:code->bits[j] numBits:code->numBits & 31];
        }
    }

    totalCompressedLength += msg.size;

    return msg.size;
}

/*
================
HuffmanDecompressText
================
*/
int HuffmanDecompressText(NSMutableData *text, NSMutableData *compressed) {
    int i, bit;
    UDBitMsg *msg;
    huffmanNode_t *node;
    int length = (int)text.length;
    unsigned char *bytes = (unsigned char *)text.mutableBytes;
    
    msg = [[UDBitMsg alloc] initWithData:compressed];

    for ( i = 0; i < length; i++ ) {
        node = huffmanTree;
        do {
            bit = [msg readBits:1];
            node = node->children[bit];
        } while (node->symbol == -1);
        bytes[i] = node->symbol;
    }
    bytes[i] = '\0';
    return (int)msg.readCount;
}

/*
================
ListHuffmanFrequencies_f
================
*/
void ListHuffmanFrequencies_f(void) {
    int        i;
    float compression;
    compression = !totalUncompressedLength ? 100 : 100 * totalCompressedLength / totalUncompressedLength;
    NSLog(@"// compression ratio = %d%%\n", (int)compression);
    NSLog(@"static int huffmanFrequencies[] = {\n");
    for (i = 0; i < MAX_HUFFMAN_SYMBOLS; i += 8) {
        NSLog(@"\t0x%08x, 0x%08x, 0x%08x, 0x%08x, 0x%08x, 0x%08x, 0x%08x, 0x%08x,\n",
                            huffmanFrequencies[i+0], huffmanFrequencies[i+1],
                            huffmanFrequencies[i+2], huffmanFrequencies[i+3],
                            huffmanFrequencies[i+4], huffmanFrequencies[i+5],
                            huffmanFrequencies[i+6], huffmanFrequencies[i+7]);
    }
    NSLog(@"}\n");
}

/*
====================================================================================

 declarations

====================================================================================
*/

@interface idDeclType : NSObject

@property (nonatomic, readonly) NSString *typeName;
@property (nonatomic, readonly) declType_t type;
@property (nonatomic, readonly) idDeclAllocator_t allocator;

-(instancetype)initWithTypeName:(NSString *)typeName type:(declType_t)type allocator:(idDeclAllocator_t)allocator;

@end

@implementation idDeclType

-(instancetype)initWithTypeName:(NSString *)typeName type:(declType_t)type allocator:(idDeclAllocator_t)allocator {
    self = [super init];
    if (self) {
        _typeName = typeName;
        _type = type;
        _allocator = allocator;
    }
    return self;
}

@end

@interface idDeclFolder : NSObject

@property (nonatomic, readonly) NSString *folder;
@property (nonatomic, readonly) NSString *extension;
@property (nonatomic, readonly) declType_t defaultType;

-(instancetype)initWithFolder:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType;

@end

@implementation idDeclFolder

-(instancetype)initWithFolder:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType {
    self = [super init];
    if (self) {
        _folder = folder;
        _extension = extension;
        _defaultType = defaultType;
    }
    return self;
}

@end

/*
static idDecl *openQ4_AllocEffectDecl( void ) {
    if ( bseAllocDeclEffect == NULL ) {
        common->FatalError( "DECL_EFFECT allocator is not installed. AttachBSE must run before declManager->Init()." );
    }

    idDecl *decl = bseAllocDeclEffect();
    if ( decl == NULL ) {
        common->FatalError( "DECL_EFFECT allocator returned NULL." );
    }

    if ( !openQ4_IsIntegratedBSEDeclEffect( decl ) ) {
        delete decl;
        common->FatalError( "DECL_EFFECT allocator returned a non-BSE decl instance." );
    }

    return decl;
}

static void openQ4_VerifyEffectDeclAllocator( void ) {
    idDecl *decl = openQ4_AllocEffectDecl();
    delete decl;
}
*/

enum declSingleFileWriteMode_t {
    DECL_SINGLEFILE_WRITE_OPENQ4 = 0,
    DECL_SINGLEFILE_WRITE_RETAIL
};

static const int DECL_GUIDE_FILE_LEXER_FLAGS =    LEXFL_NOSTRINGCONCAT |
                                                LEXFL_NOSTRINGESCAPECHARS |
                                                LEXFL_ALLOWPATHNAMES;
static NSString *DECL_GUIDE_FOLDER = @"guides";
static NSString *DECL_GUIDE_EXTENSION = @".guide";
static NSString *DECL_GUIDE_PATH_PREFIX = @"guides/";
static NSString *DECL_WRITE_PROGRAM_IMAGES_CVAR = @"image_writeProgramImages";

@class idDeclFile;

@implementation idDeclBase

@end

@interface idDecl()

@property (nonatomic, weak) idDeclBase *base;
@property (weak, nonatomic, readwrite) idDeclManager *declManager;

@end

@implementation idDecl

-(instancetype)init {
    self = [super init];
    if (self) {
        self.base = nil;
    }
    return self;
}

-(NSString *)name { return _base.name; }
-(declType_t)declType { return _base.declType; }
-(declState_t)state { return [_base state]; }
-(BOOL)isImplicit { return [_base isImplicit]; }
-(BOOL)isValid { return [_base isValid]; }
-(void)invalidate { [_base invalidate]; }
-(void)ensureNotPurged { [_base ensureNotPurged]; }
-(int)index { return [_base index]; }
-(int)lineNum { return [_base lineNum]; }
-(NSString *)fileName { return [_base fileName]; }
-(void)text:(NSMutableData *)text { [_base text:text]; }
-(int)textLength { return [_base textLength]; }
-(int)compressedLength { return [_base compressedLength]; }
-(void)setText:(NSMutableData *)text { [_base setText:text]; }
-(BOOL)replaceSourceFileText:(NSError **)error { return [_base replaceSourceFileText:error]; }
-(BOOL)sourceFileChanged { return [_base sourceFileChanged]; }
-(BOOL)makeDefault:(NSError **)error { return [_base makeDefault:error]; }
-(BOOL)everReferenced { return [_base everReferenced]; }

-(NSString *)defaultDefinition { return _base.defaultDefinition; }
-(void)freeData { [_base freeData]; }
-(size_t)size { return [_base size]; }
-(void)list { [_base list]; }

-(BOOL)parse:(NSMutableData *)text error:(NSError **)error {
    return [_base parse:text noCaching:NO error:error];
}

-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error {
    return [_base parse:text noCaching:noCaching error:error];
}

-(void)print {
    [_base print];
}

-(BOOL)rebuildTextSource {
    return [_base rebuildTextSource];
}

-(BOOL)setDefaultText {
    return [_base setDefaultText];
}

-(void)setReferencedThisLevel {
    [_base setReferencedThisLevel];
}

-(BOOL)validate:(NSMutableData *)psText reportTo:(NSMutableString *)strReportTo {
    return [_base validate:psText reportTo:strReportTo];
}

@end

@interface idDeclLocal : idDeclBase {
@public
    idDecl *                    selfDecl;
    BOOL                        insideLevelLoad;
    NSMutableString *           name;                     // name of the decl
    NSMutableData *             textSource;               // decl text definition
    int                         textLength;               // length of textSource
    idDeclFile *                sourceFile;               // source file in which the decl was defined
    int                         sourceTextOffset;         // offset in source file to decl text
    int                         sourceTextLength;         // length of decl text in source file
    int                         sourceLine;               // this is where the actual declaration token starts
    int                         checksum;                 // checksum of the decl text
    declType_t                  type;                     // decl type
    declState_t                 declState;                // decl state
    int                         index;                    // index in the per-type list

    BOOL                        parsedOutsideLevelLoad;   // these decls will never be purged
    BOOL                        everReferenced;           // set to true if the decl was ever used
    BOOL                        referencedThisLevel;      // set to true when the decl is used for the current level
    BOOL                        redefinedInReload;        // used during file reloading to make sure a decl that has
                                                          // its source removed will be defaulted
    BOOL                        needsPrecache;            // packed decl stubs expand source text lazily when first parsed
    idDeclLocal *               nextInFile;              // next decl in the decl file
    __weak idDeclManager *      declManager;
}

-(void)allocateSelf;

// Parses the decl definition.
// After calling parse, a decl will be guaranteed usable.
-(BOOL)parseLocal:(BOOL)noCaching error:(NSError **)error; // = NO

// Does a makeDefault, but flags the decl so that it
// will parse() the next time the decl is found.
-(void)purge;

// Set textSource possible with compression.
-(void)setTextLocal:(NSMutableData *)text;

@end

/*
static bool DeclManager_IsopenQ4OverrideDeclFile( const idDeclFile *sourceFile ) {
    if ( sourceFile == NULL ) {
        return false;
    }

    idStr fileName = sourceFile->fileName;
    fileName.BackSlashesToSlashes();
    return fileName.Icmpn( "def/", 4 ) == 0 && fileName.Find( "_openq4.def", false ) >= 0;
}

static bool DeclManager_DeclNameHasPrefix( const idStr &name, const char *prefix ) {
    return name.Icmpn( prefix, strlen( prefix ) ) == 0;
}

static bool DeclManager_IsStockMaterialRedeclaration( declType_t type, const idStr &name, const idDeclFile *previousSourceFile, const idDeclFile *currentSourceFile ) {
    if ( type != DECL_MATERIAL || previousSourceFile == NULL || currentSourceFile == NULL ) {
        return false;
    }

    if ( DeclManager_IsopenQ4OverrideDeclFile( previousSourceFile ) || DeclManager_IsopenQ4OverrideDeclFile( currentSourceFile ) ) {
        return false;
    }

    idStr previousFileName = previousSourceFile->fileName;
    previousFileName.BackSlashesToSlashes();

    idStr currentFileName = currentSourceFile->fileName;
    currentFileName.BackSlashesToSlashes();

    if ( currentFileName.Icmp( "materials/mappack1.mtr" ) == 0 && previousFileName.Icmp( "materials/mapobjects_mp2.mtr" ) == 0 ) {
        return DeclManager_DeclNameHasPrefix( name, "models/mapobjects/multiplayer/jump_pad/" ) ||
            DeclManager_DeclNameHasPrefix( name, "models/mapobjects/multiplayer/acceleration_pad/" );
    }

    if ( currentFileName.Icmp( "materials/stroyent_mp.mtr" ) == 0 && previousFileName.Icmp( "materials/mappack1.mtr" ) == 0 ) {
        return DeclManager_DeclNameHasPrefix( name, "textures/stroyent/mp/" );
    }

    return false;
}*/

static const declType_t declSingleFileFrameworkTypes[] = {
    DECL_TABLE,
    DECL_MATERIAL,
    DECL_SKIN,
    DECL_SOUND,
    DECL_MATERIALTYPE,
    DECL_LIPSYNC,
    DECL_PLAYBACK,
    DECL_EFFECT,
    DECL_PDA,
    DECL_VIDEO,
    DECL_AUDIO,
    DECL_EMAIL,
    DECL_MAPDEF
};

static const declType_t declSingleFileopenQ4GameTypes[] = {
    DECL_ENTITYDEF,
    DECL_MODELDEF,
    DECL_MAPDEF,
    DECL_CAMERADEF,
    DECL_AF,
    DECL_MODELEXPORT,
    DECL_PLAYER_MODEL
};

static const declType_t declSingleFileRetailGameTypes[] = {
    DECL_ENTITYDEF,
    DECL_MAPDEF,
    DECL_CAMERADEF,
    DECL_AF,
    DECL_MODELEXPORT
};

/*
static void DeclManager_ShowReloadProgress( int fileIndex, int fileCount, const char *fileName ) {
    openQ4_ToolPrint( va( "%d/%d: %s\n", fileIndex + 1, fileCount, fileName ) );
}

idDeclManagerLocal    declManagerLocal;
idDeclManager *        declManager = &declManagerLocal;

static rvDeclGuide *DeclManager_FindGuide( const char *name ) {
    rvDeclGuide **guide;
    if ( declManagerLocal.guideTable.Get( name, &guide ) ) {
        return *guide;
    }
    return NULL;
}

static void DeclManager_SetGuide( rvDeclGuide *guide ) {
    if ( guide == NULL ) {
        return;
    }

    rvDeclGuide *storedGuide = guide;
    declManagerLocal.guideTable.Set( guide->GetName(), storedGuide );
}

static void DeclManager_ClearGuides( void ) {
    declManagerLocal.guideTable.DeleteContents();
}*/

@interface idDeclFile : NSObject {
@public
    NSMutableString*                 fileName;
    declType_t                       defaultType;

    unsigned int                     timestamp;
    int                              checksum;
    int                              fileSize;
    int                              numLines;

    idDeclLocal *                    decls;
    __weak idDeclManager *           declManager;
}

-(instancetype)init;
-(instancetype)initWithFileName:(NSString *)filename defaultType:(declType_t)defaultType manager:(idDeclManager *)manager;

-(int)reload:(BOOL)force error:(NSError **)error;

-(int)loadAndParse:(BOOL)unique error:(NSError **)error; // unique = false by default
-(int)loadAndParseFrom:(idFile *)file error:(NSError **)error;

@end

@interface idDeclManager (Local)

-(void)incrIndent;
-(void)decrIndent;

-(void)setInsideLoad:(BOOL)var;
-(BOOL)insideLoad;
-(instancetype)init;
-(void)shutdown;
-(void)reload:(BOOL)force error:(NSError **)error;

// RAVEN BEGIN
// jscott: precache any guide (template) files
-(void)parseGuides;
-(void)shutdownGuides;
-(BOOL)evaluateGuide:(NSMutableString *)name source:(idLexer *)src definition:(NSMutableString *)definition error:(NSError **)error;
-(BOOL)evaluateInlineGuide:(NSMutableString *)name definition:(NSMutableString *)definition error:(NSError **)error;
// RAVEN END

-(void)beginLevelLoad;
-(void)endLevelLoad;
-(void)registerDeclType:(declType_t)type typeName:(NSString *)typeName allocator:(idDeclAllocator_t)allocator;
-(void)startLoadingDecls;
-(void)finishLoadingDecls;
-(BOOL)loadDeclsFromFile:(NSError **)error;
-(BOOL)writeDeclFile:(NSError **)error;
-(void)flushDecls;

-(BOOL)registerDeclFolderWrapper:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType unique:(BOOL)unique nonrecursive:(BOOL)norecurse error:(NSError **)error;
-(BOOL)registerDeclFolderWrapper:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType unique:(BOOL)unique error:(NSError **)error; // nonrecursive=NO
-(BOOL)registerDeclFolderWrapper:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType nonrecursive:(BOOL)norecurse error:(NSError **)error; // unique=NO
-(BOOL)registerDeclFolderWrapper:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType error:(NSError **)error; // unique=NO, nonrecursive=NO

-(BOOL)registerDeclFolder:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType error:(NSError **)error;
-(int)checksum;
-(int)numDeclTypes;
-(int)numDecls:(declType_t)type;
-(NSString *)declNameFromType:(declType_t)type;
-(declType_t)declTypeFromName:(NSString *)typeName;
-(idDecl *)findType:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault noCaching:(BOOL)noCaching error:(NSError **)error;
-(idDecl *)findType:(declType_t)type name:(NSString *)name noCaching:(BOOL)noCaching error:(NSError **)error; // makeDefault=YES
-(idDecl *)findType:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error; // noCaching=NO
-(idDecl *)findType:(declType_t)type name:(NSString *)name error:(NSError **)error; // makeDefault=YES, noCaching=NO

//-(idDecl *)declByIndex:(int)index type:(declType_t)type forceParse:(BOOL)forceParse error:(NSError **)error;
//-(idDecl *)declByIndex:(int)index type:(declType_t)type error:(NSError **)error; // forceParse=YES

-(idDecl *)findDeclWithoutParsing:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault;
-(idDecl *)findDeclWithoutParsing:(declType_t)type name:(NSString *)name; // makeDefault = YES
-(void)reloadFile:(NSString *)filename force:(BOOL)force;

//-(void)listType:(declType_t)type;
//-(void)printType:(declType_t)type;

-(idDecl *)createNewDecl:(declType_t)type name:(NSString *)name fileName:(NSString *)fileName;

//BSM Added for the material editors rename capabilities
-(BOOL)renameDecl:(declType_t)type fromName:(NSString *)oldName toName:(NSString *)newName;

-(void)mediaPrint:(NSString *)fmt, ...;
-(void)writePrecacheCommands:(idFile *)f;
/*
// Convenience functions for specific types.
virtual    const idMaterial *        FindMaterial( const char *name, bool makeDefault = true );
virtual const idDeclTable *        FindTable( const char *name, bool makeDefault = true );
virtual const idDeclSkin *        FindSkin( const char *name, bool makeDefault = true );
virtual const idSoundShader *    FindSound( const char *name, bool makeDefault = true );
// RAVEN BEGIN
// jscott: for new Raven decls
virtual const rvDeclMatType *    FindMaterialType( const char *name, bool makeDefault = true );
virtual    const rvDeclLipSync *    FindLipSync( const char *name, bool makeDefault = true );
virtual    const rvDeclPlayback *    FindPlayback( const char *name, bool makeDefault = true );
virtual    const rvDeclEffect *    FindEffect( const char *name, bool makeDefault = true );
// RAVEN END

virtual const idMaterial *        MaterialByIndex( int index, bool forceParse = true );
virtual const idDeclTable *        TableByIndex( int index, bool forceParse = true );
virtual const idDeclSkin *        SkinByIndex( int index, bool forceParse = true );
virtual const idSoundShader *    SoundByIndex( int index, bool forceParse = true );
// RAVEN BEGIN
// jscott: for new Raven decls
virtual const rvDeclMatType *    MaterialTypeByIndex( int index, bool forceParse = true );
virtual const rvDeclLipSync *    LipSyncByIndex( int index, bool forceParse = true );
virtual    const rvDeclPlayback *    PlaybackByIndex( int index, bool forceParse = true );
virtual const rvDeclEffect *    EffectByIndex( int index, bool forceParse = true );

virtual void                    StartPlaybackRecord( rvDeclPlayback *playback );
virtual bool                    SetPlaybackData( rvDeclPlayback *playback, int now, int control, class rvDeclPlaybackData *pbd );
virtual bool                    GetPlaybackData( const rvDeclPlayback *playback, int control, int now, int last, class rvDeclPlaybackData *pbd );
virtual bool                    FinishPlayback( rvDeclPlayback *playback );
*/
-(NSString *)newName:(declType_t)type base:(NSString *)base;
-(NSString *)declTypeName:(declType_t)type;
-(size_t)listDeclSummary;
-(void)removeDeclFile:(NSString *)file;
-(BOOL)validate:(declType_t)type index:(int)iIndex reportTo:(NSMutableString *)strReportTo;
-(idDecl *)allocateDecl:(declType_t)type;
//virtual byte *                    GetMaterialTypeArray( const char *image, int &width, int &height );

+(void)makeNameCanonical:(NSString *)name result:(char *)result maxLength:(int)maxLength;
-(idDeclLocal *)findTypeWithoutParsing:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault/*true*/ indexToStoreAt:(int)indexToStoreAt;//-1
-(idDeclLocal *)findTypeWithoutParsing:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault/*true*/;
-(idDeclLocal *)findTypeWithoutParsing:(declType_t)type name:(NSString *)name indexToStoreAt:(int)indexToStoreAt;//-1
-(idDeclLocal *)findTypeWithoutParsing:(declType_t)type name:(NSString *)name;

-(idDeclType *)declType:(int)type; // { return declTypes[type]; }
-(const idDeclFile *)implicitDeclFile; // ( void ) const { return &implicitDecls; }

/*
idHashTable<rvDeclGuide *>    guideTable;
private:
void                        RegisterDeclFolder( const char *folder, const char *extension, declType_t defaultType, bool unique, bool norecurse );
idDeclFile *                FindLoadedDeclFile( const char *fileName );
idDeclFile *                FindOrCreateLoadedDeclFile( const char *fileName, declType_t defaultType );
idDeclFolder *                FindOrCreateDeclFolder( const char *folder, const char *extension, declType_t defaultType );
bool                        TypeListContains( const idList<declType_t> &types, declType_t type ) const;
int                            GetTotalTextMemory( declType_t type );
int                            NumWritableDecls( idDeclFile *declFile, const idList<declType_t> &typesToWrite, bool writeStubs );
void                        BuildPackedDeclText( idDeclLocal *decl, idStr &declText );
void                        WriteDeclFileWithMode( declSingleFileWriteMode_t writeMode );
void                        WriteDecls( idFile *file, idDeclFile *declFile, const idList<declType_t> &typesToWrite, bool writeStubs );
void                        WriteSingleDeclSection( idFile *file, const idList<declType_t> &typesToWrite, bool writeStubs );
void                        CheckDecls( void );
void                        DeleteLocalDecl( idDeclLocal *decl );
rvDeclGuide *                GetNewGuide( idLexer *src, idStr &file );

private:
static void                    ListAllDecls_f( const idCmdArgs &args );
static void                    ListDecls_f( const idCmdArgs &args );
static void                    ReloadDecls_f( const idCmdArgs &args );
static void                    ReloadFile_f( const idCmdArgs &args );
static void                    ResaveDecl_f( const idCmdArgs &args );
static void                    WriteDeclFile_f( const idCmdArgs &args );
static void                    FlushDecls_f( const idCmdArgs &args );
static void                    CheckDecls_f( const idCmdArgs &args );
static void                    TouchDecl_f( const idCmdArgs &args );
*/

@end

static void DeclManager_GetSingleDeclFileName(UDWorkspace *workspace, NSMutableString *fileName) {
    NSString *overrideName = workspace.com_singleDeclFileName;
    if (overrideName != nil && overrideName.length > 0) {
        [fileName setString:overrideName];
        return;
    }

    /*
    const char *assetLogName = fileSystem->GetAssetLogName();
    if ( assetLogName != NULL && assetLogName[0] != '\0' ) {
        const char *baseName = assetLogName;
        const char *slash = strchr( assetLogName, '/' );
        if ( slash != NULL ) {
            baseName = slash + 1;
        }
        fileName = baseName;
        fileName.SetFileExtension( ".decls" );
        return;
    }*/

    [fileName setString:@"default.decls"];
}

static int c_savedMemory = 0;

static BOOL readPackedDeclLine(idFile *file, NSMutableString *line, NSError **error) {
    [line setString:@""];
    
    char ch;
    while ([file read:&ch length:1 error:error] == 1) {
        if (ch == '\n') {
            return YES;
        }
        if (ch != '\r') {
            [line appendFormat:@"%C", ch];
        }
    }
    
    return line.length > 0;
}

static void makeDeclTypeList(NSMutableSet<NSNumber *> *list, const declType_t *types, int numTypes) {
    [list removeAllObjects];
    for (int i = 0; i < numTypes; i++) {
        [list addObject:@(types[i])];
    }
}

static const char *DeclManager_GetSingleDeclWriteModeName(enum declSingleFileWriteMode_t writeMode) {
    switch (writeMode) {
        case DECL_SINGLEFILE_WRITE_RETAIL:
            return "retail";
            
        case DECL_SINGLEFILE_WRITE_OPENQ4:
        default:
            return "openq4";
    }
}

static enum declSingleFileWriteMode_t DeclManager_GetConfiguredSingleDeclWriteMode(UDWorkspace *workspace) {
    if (workspace.com_singleDeclFileWriteMode == DECL_SINGLEFILE_WRITE_RETAIL) {
        return DECL_SINGLEFILE_WRITE_RETAIL;
    }
    
    return DECL_SINGLEFILE_WRITE_OPENQ4;
}
/*
static bool DeclManager_ParseSingleDeclWriteMode( const char *modeName, declSingleFileWriteMode_t &writeMode ) {
    if ( modeName == NULL || modeName[0] == '\0' ) {
        return false;
    }
    
    if ( !idStr::Icmp( modeName, "openq4" ) || !idStr::Icmp( modeName, "0" ) ) {
        writeMode = DECL_SINGLEFILE_WRITE_OPENQ4;
        return true;
    }
    
    if ( !idStr::Icmp( modeName, "retail" ) || !idStr::Icmp( modeName, "1" ) ) {
        writeMode = DECL_SINGLEFILE_WRITE_RETAIL;
        return true;
    }
    
    return false;
}*/

static void DeclManager_MakeGameDeclTypeList(NSMutableSet<NSNumber *> *list, enum declSingleFileWriteMode_t writeMode ) {
    if (writeMode == DECL_SINGLEFILE_WRITE_RETAIL) {
        makeDeclTypeList(list, declSingleFileRetailGameTypes, sizeof(declSingleFileRetailGameTypes) / sizeof(declSingleFileRetailGameTypes[0]));
        return;
    }
    
    makeDeclTypeList(list, declSingleFileopenQ4GameTypes, sizeof(declSingleFileopenQ4GameTypes) / sizeof(declSingleFileopenQ4GameTypes[0]));
}

static BOOL DeclManager_WriteProgramImagesEnabled(void) {
    /*
    return cvarSystem != NULL &&
    cvarSystem->GetCVarBool( DECL_WRITE_PROGRAM_IMAGES_CVAR ) &&
    renderSystem != NULL &&
    renderSystem->IsOpenGLRunning();
    */
    return NO;
}

@interface idDeclManager (Enumerator)

- (int)numDeclTypes;
- (idDeclType *)declTypeAtIndex:(int)typeIndex;
- (NSArray<idDeclLocal *> *)linearListAtTypeIndex:(int)typeIndex;

@end

@implementation UDDeclEnumerator {
    idDeclManager *_manager;
    declType_t     _type;
    BOOL           _forceParse;
}

- (instancetype)initWithManager:(idDeclManager *)manager
                           type:(declType_t)type
                     forceParse:(BOOL)forceParse
{
    self = [super init];
    if (self) {
        _manager = manager;
        _type = type;
        _forceParse = forceParse;
    }
    return self;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)len
{
    int typeIndex = (int)_type;

    if (typeIndex < 0 ||
        typeIndex >= [_manager numDeclTypes] ||
        [_manager declTypeAtIndex:typeIndex] == nil) {
        return 0;
    }

    NSArray *list = [_manager linearListAtTypeIndex:typeIndex];
    // list elements are idDeclLocal *

    if (state->state == 0) {
        // mutation guard: pointer identity of the list (or a generation counter)
        state->mutationsPtr = &state->extra[0];
        state->extra[0] = (unsigned long)list;
    }

    NSUInteger collected = 0;
    NSUInteger i = state->state;

    while (i < list.count && collected < len) {
        idDeclLocal *local = [list objectAtIndex:i++];
        if (local == nil) {
            continue; // ready for tombstones later
        }

        [local allocateSelf];

        if (_forceParse && local->declState == DS_UNPARSED) {
            NSError *error = nil;
            if (![local parseLocal:NO error:&error]) {
                continue; // or still yield; match your declByIndex policy
            }
        }

        idDecl *decl = local->selfDecl;
        if (decl == nil) {
            continue;
        }

        buffer[collected++] = decl;
    }

    state->state = i;
    state->itemsPtr = buffer;
    return collected;
}

@end

@implementation idDeclManager {
    idDeclType *                          declTypes[DECL_MAX_TYPES];
    NSMutableArray<idDeclFolder *> *      declFolders;
    
    NSMutableArray<idDeclFile *> *        loadedFiles;
    NSMutableDictionary *                 hashTables[DECL_MAX_TYPES];
    NSMutableArray<idDeclLocal *> *       linearLists[DECL_MAX_TYPES];
    idDeclFile *                          implicitDecls;    // this holds all the decls that were created because explicit
    // text definitions were not found. Decls that became default
    // because of a parse error are not in this list.
    int                                   checksum;         // checksum of all loaded decl text
    int                                   indent;           // for MediaPrint
    bool                                  insideLevelLoad;
    idFile *                              singleDeclFile;
}

/*
 idCVar com_SingleDeclFile( "com_SingleDeclFile", "0", CVAR_SYSTEM | CVAR_BOOL, "load decls from a packed single .decls file instead of scanning loose decl folders" );
 static idCVar com_singleDeclFileName( "com_singleDeclFileName", "", CVAR_SYSTEM, "override packed decl file used by com_SingleDeclFile and writeDeclFile" );
 static idCVar com_singleDeclFileWriteMode( "com_singleDeclFileWriteMode", "0", CVAR_SYSTEM | CVAR_INTEGER, "packed .decls writer policy: 0 = openQ4 extended game types, 1 = exact retail game types", 0, 1, idCmdSystem::ArgCompletion_Integer<0,1> );
 */

-(void)incrIndent {
    indent++;
}

-(void)decrIndent {
    indent--;
}

- (instancetype)initWithWorkspace:(UDWorkspace *)workspace {
    
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _workspace = workspace;

    self->declFolders = [[NSMutableArray alloc] init];
    self->loadedFiles = [[NSMutableArray alloc] init];
    
    for (int i = 0; i < DECL_MAX_TYPES; i++) {
        self->hashTables[i] = [[NSMutableDictionary alloc] init];
        self->linearLists[i] = [[NSMutableArray alloc] init];
    }

    self->implicitDecls = [[idDeclFile alloc] initWithFileName:@"implicit" defaultType:0 manager:self];
    self->indent = 0;
    self->insideLevelLoad = NO;
    self->singleDeclFile = nil;
    
    checksum = 0;
            
    return self;
}

+(void)initialize {
#ifdef USE_COMPRESSED_DECLS
    SetupHuffman();
#endif
    
#ifdef GET_HUFFMAN_FREQUENCIES
    ClearHuffmanFrequencies();
#endif
}

+(void)shutdown { // TODO: make this actually work.
#ifdef USE_COMPRESSED_DECLS
    ShutdownHuffman();
#endif
}

-(BOOL)startup:(NSError **)error {
    NSLog(@"----- Initializing Decls -----");

    // jmarshall - template(guide) Support
    [self parseGuides];
    // jmarshall end

    // decls used throughout the engine
    [self registerDeclType:DECL_TABLE typeName:@"table" allocator:&idDeclTable_Allocator];
    [self registerDeclType:DECL_MATERIAL typeName:@"material" allocator:&idDeclMaterial_Allocator];
    [self registerDeclType:DECL_SKIN typeName:@"skin" allocator:&idDeclSkin_Allocator];
    /*
    [self registerDeclType:DECL_SOUND typeName:@"sound" allocator:NULL];
    [self registerDeclType:DECL_ENTITYDEF typeName:@"entityDef" allocator:NULL];
    [self registerDeclType:DECL_MAPDEF typeName:@"mapDef" allocator:NULL];

     // jmarshall: Raven Decl Support
     RegisterDeclType(  "materialType",        DECL_MATERIALTYPE,  idDeclAllocator<rvDeclMatType>);
     RegisterDeclType(  "lipSync",            DECL_LIPSYNC,        idDeclAllocator<rvDeclLipSync>);
     RegisterDeclType(  "playback",            DECL_PLAYBACK,        idDeclAllocator<rvDeclPlayback>);
     openQ4_VerifyEffectDeclAllocator();
     RegisterDeclType(    "effect",            DECL_EFFECT,        openQ4_AllocEffectDecl);
     // jmarshall end
     */
     // jmarshall: Raven Decl Support
     //RegisterDeclType( "fx",                    DECL_FX,            idDeclAllocator<idDeclFX> );
    [self registerDeclType:DECL_PARTICLE typeName:@"particle" allocator:&idDeclAllocator_idDeclParticle];
     // jmarshall end
     //RegisterDeclType( "articulatedFigure",    DECL_AF,            idDeclAllocator<idDeclAF> );
    [self registerDeclType:DECL_PDA typeName:@"pda" allocator:&idDeclPDA_Allocator];
    [self registerDeclType:DECL_EMAIL typeName:@"email" allocator:&idDeclEmail_Allocator];
    [self registerDeclType:DECL_VIDEO typeName:@"video" allocator:&idDeclVideo_Allocator];
    [self registerDeclType:DECL_AUDIO typeName:@"audio" allocator:&idDeclAudio_Allocator];
    /*
     RegisterDeclType( "playerModel",            DECL_PLAYER_MODEL,    idDeclAllocator<rvDeclPlayerModel> );
     */

    if (_workspace.com_SingleDeclFile) {
        [self startLoadingDecls];
        if (![self loadDeclsFromFile:error]) {
            return NO;
        }
         //cmdSystem->AddCommand( "flushDecls", FlushDecls_f, CMD_FL_SYSTEM, "deallocates current decl data" );
         //cmdSystem->AddCommand( "checkDecls", CheckDecls_f, CMD_FL_SYSTEM, "parses every loaded decl" );
    } else {
        //cmdSystem->AddCommand( "writeDeclFile", WriteDeclFile_f, CMD_FL_SYSTEM, "writes parsed decls to a packed .decls file (optional mode: openq4 or retail)" );
        
        if (![self registerDeclFolderWrapper:@"materials" extension:@".mtr" defaultType:DECL_MATERIAL error:error]) {
            return NO;
        }
        if (![self registerDeclFolderWrapper:@"skins" extension:@".skin" defaultType:DECL_SKIN error:error]) {
            return NO;
        }
         /*RegisterDeclFolderWrapper( "sound",            ".sndshd",        DECL_SOUND, false, true );
         
         // jmarshall: Raven Decl Support
         RegisterDeclFolderWrapper( "materials/types",    ".mtt",            DECL_MATERIALTYPE );
         RegisterDeclFolderWrapper( "lipsync",            ".lipsync",        DECL_LIPSYNC );
         RegisterDeclFolderWrapper( "playbacks",            ".playback",    DECL_PLAYBACK, true );
         RegisterDeclFolderWrapper( "effects",            ".fx",            DECL_EFFECT, true );
         // jmarshall end
         */
        
        // NOTE: in doom3, these are registered in the game dll
        /*
         declManager->RegisterDeclFolder( "def",                ".def",                DECL_ENTITYDEF );
         declManager->RegisterDeclFolder( "fx",                ".fx",                DECL_FX );
        */
        [self registerDeclFolder:@"particles" extension:@".prt" declType:DECL_PARTICLE error:error];
        /*
         declManager->RegisterDeclFolder( "af",                ".af",                DECL_AF );
        */
        [self registerDeclFolder:@"newpdas" extension:@".pda" declType:DECL_PDA error:error];
    }
    /*
     // add console commands
     cmdSystem->AddCommand( "listDecls", ListDecls_f, CMD_FL_SYSTEM, "lists all decls" );
     cmdSystem->AddCommand( "listAllDecls", ListAllDecls_f, CMD_FL_SYSTEM, "lists every decl name grouped by type" );
     
     cmdSystem->AddCommand( "reloadDecls", ReloadDecls_f, CMD_FL_SYSTEM, "reloads decls" );
     cmdSystem->AddCommand( "reloadFile", ReloadFile_f, CMD_FL_SYSTEM, "reloads a single decl file" );
     cmdSystem->AddCommand( "resaveDecl", ResaveDecl_f, CMD_FL_SYSTEM, "resaves one decl or every decl of a type" );
     cmdSystem->AddCommand( "touch", TouchDecl_f, CMD_FL_SYSTEM, "touches a decl" );
     
     cmdSystem->AddCommand( "listTables", idListDecls_f<DECL_TABLE>, CMD_FL_SYSTEM, "lists tables", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listMaterials", idListDecls_f<DECL_MATERIAL>, CMD_FL_SYSTEM, "lists materials", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listSkins", idListDecls_f<DECL_SKIN>, CMD_FL_SYSTEM, "lists skins", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listSoundShaders", idListDecls_f<DECL_SOUND>, CMD_FL_SYSTEM, "lists sound shaders", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     
     cmdSystem->AddCommand( "listEntityDefs", idListDecls_f<DECL_ENTITYDEF>, CMD_FL_SYSTEM, "lists entity defs", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     //cmdSystem->AddCommand( "listFX", idListDecls_f<DECL_FX>, CMD_FL_SYSTEM, "lists FX systems", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     //cmdSystem->AddCommand( "listParticles", idListDecls_f<DECL_PARTICLE>, CMD_FL_SYSTEM, "lists particle systems", idCmdSystem::ArgCompletion_String<listDeclStrings> //);
     cmdSystem->AddCommand( "listAF", idListDecls_f<DECL_AF>, CMD_FL_SYSTEM, "lists articulated figures", idCmdSystem::ArgCompletion_String<listDeclStrings>);
     cmdSystem->AddCommand( "listPDAs", idListDecls_f<DECL_PDA>, CMD_FL_SYSTEM, "lists PDAs", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listEmails", idListDecls_f<DECL_EMAIL>, CMD_FL_SYSTEM, "lists Emails", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listVideos", idListDecls_f<DECL_VIDEO>, CMD_FL_SYSTEM, "lists Videos", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listAudios", idListDecls_f<DECL_AUDIO>, CMD_FL_SYSTEM, "lists Audios", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listMaterialTypes", idListDecls_f<DECL_MATERIALTYPE>, CMD_FL_SYSTEM, "lists material types", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listLipsyncs", idListDecls_f<DECL_LIPSYNC>, CMD_FL_SYSTEM, "lists lip sync decls", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listPlaybacks", idListDecls_f<DECL_PLAYBACK>, CMD_FL_SYSTEM, "lists playback decls", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     cmdSystem->AddCommand( "listEffects", idListDecls_f<DECL_EFFECT>, CMD_FL_SYSTEM, "lists effects", idCmdSystem::ArgCompletion_String<listDeclStrings> );
     
     cmdSystem->AddCommand( "printTable", idPrintDecls_f<DECL_TABLE>, CMD_FL_SYSTEM, "prints a table", idCmdSystem::ArgCompletion_Decl<DECL_TABLE> );
     cmdSystem->AddCommand( "printMaterial", idPrintDecls_f<DECL_MATERIAL>, CMD_FL_SYSTEM, "prints a material", idCmdSystem::ArgCompletion_Decl<DECL_MATERIAL> );
     cmdSystem->AddCommand( "printSkin", idPrintDecls_f<DECL_SKIN>, CMD_FL_SYSTEM, "prints a skin", idCmdSystem::ArgCompletion_Decl<DECL_SKIN> );
     cmdSystem->AddCommand( "printSoundShader", idPrintDecls_f<DECL_SOUND>, CMD_FL_SYSTEM, "prints a sound shader", idCmdSystem::ArgCompletion_Decl<DECL_SOUND> );
     
     cmdSystem->AddCommand( "printEntityDef", idPrintDecls_f<DECL_ENTITYDEF>, CMD_FL_SYSTEM, "prints an entity def", idCmdSystem::ArgCompletion_Decl<DECL_ENTITYDEF> );
     //cmdSystem->AddCommand( "printFX", idPrintDecls_f<DECL_FX>, CMD_FL_SYSTEM, "prints an FX system", idCmdSystem::ArgCompletion_Decl<DECL_FX> );
     //    cmdSystem->AddCommand( "printParticle", idPrintDecls_f<DECL_PARTICLE>, CMD_FL_SYSTEM, "prints a particle system", idCmdSystem::ArgCompletion_Decl<DECL_PARTICLE> );
     cmdSystem->AddCommand( "printAF", idPrintDecls_f<DECL_AF>, CMD_FL_SYSTEM, "prints an articulated figure", idCmdSystem::ArgCompletion_Decl<DECL_AF> );
     cmdSystem->AddCommand( "printPDA", idPrintDecls_f<DECL_PDA>, CMD_FL_SYSTEM, "prints an PDA", idCmdSystem::ArgCompletion_Decl<DECL_PDA> );
     cmdSystem->AddCommand( "printEmail", idPrintDecls_f<DECL_EMAIL>, CMD_FL_SYSTEM, "prints an Email", idCmdSystem::ArgCompletion_Decl<DECL_EMAIL> );
     cmdSystem->AddCommand( "printVideo", idPrintDecls_f<DECL_VIDEO>, CMD_FL_SYSTEM, "prints a Audio", idCmdSystem::ArgCompletion_Decl<DECL_VIDEO> );
     cmdSystem->AddCommand( "printAudio", idPrintDecls_f<DECL_AUDIO>, CMD_FL_SYSTEM, "prints an Video", idCmdSystem::ArgCompletion_Decl<DECL_AUDIO> );
     cmdSystem->AddCommand( "printMaterialTypes", idPrintDecls_f<DECL_MATERIALTYPE>, CMD_FL_SYSTEM, "prints material types", idCmdSystem::ArgCompletion_Decl<DECL_MATERIALTYPE> );
     cmdSystem->AddCommand( "printLipsyncs", idPrintDecls_f<DECL_LIPSYNC>, CMD_FL_SYSTEM, "prints lip syncs", idCmdSystem::ArgCompletion_Decl<DECL_LIPSYNC> );
     cmdSystem->AddCommand( "printPlaybacks", idPrintDecls_f<DECL_PLAYBACK>, CMD_FL_SYSTEM, "prints playbacks", idCmdSystem::ArgCompletion_Decl<DECL_PLAYBACK> );
     cmdSystem->AddCommand( "printEffects", idPrintDecls_f<DECL_EFFECT>, CMD_FL_SYSTEM, "prints effects", idCmdSystem::ArgCompletion_Decl<DECL_EFFECT> );
     
     cmdSystem->AddCommand( "listHuffmanFrequencies", ListHuffmanFrequencies_f, CMD_FL_SYSTEM, "lists decl text character frequencies" );
     */
    NSLog(@"------------------------------");

    return YES;
}

-(void)shutdown {
    int            i, j;
    idDeclLocal *decl;
    
    [self finishLoadingDecls];
    //[self shutdownGuides];
    
    // free decls
    for (i = 0; i < DECL_MAX_TYPES; i++) {
        for (j = 0; j < linearLists[i].count; j++) {
            decl = linearLists[i][j];
            if (decl->selfDecl != nil) {
                [decl->selfDecl freeData];
                decl->selfDecl = nil;
            }
            if (decl->textSource) {
                //free(decl->textSource);
                decl->textSource = nil;
            }
            decl = nil;
        }
        [linearLists[i] removeAllObjects];
        [hashTables[i] removeAllObjects];
    }
    
    // free decl files
    loadedFiles = nil; // loadedFiles.DeleteContents(YES);
    
    // free the decl types and folders
    //declTypes.DeleteContents(true)
    for (i = 0; i < DECL_MAX_TYPES; i++) {
        declTypes[i] = nil;;
    }
    declFolders = nil; //declFolders.DeleteContents(YES);
}

-(void)dealloc {
    [self shutdown];
}

-(void)parseGuides {
    /*
    common->Printf( "Loading guides.... " );
    ShutdownGuides();
    
    idFileList *fileList = fileSystem->ListFiles( DECL_GUIDE_FOLDER, DECL_GUIDE_EXTENSION, true );
    for ( int i = 0; fileList != NULL && i < fileList->GetNumFiles(); i++ ) {
        idLexer src;
        idToken    token;
        idStr fileName = fileList->GetList()[i];
        idStr fullPath = DECL_GUIDE_PATH_PREFIX;
        fullPath += fileName;
        
        if ( !src.LoadFile( fullPath.c_str() ) ) {
            fileSystem->FreeFileList( fileList );
            common->Printf( "\n" );
            common->FatalError( "Couldn't load %s", fullPath.c_str() );
            return;
        }
        src.SetFlags( DECL_GUIDE_FILE_LEXER_FLAGS );
        
        while ( src.ReadToken( &token ) ) {
            if ( token.Icmp( "guide" ) == 0 ) {
                rvDeclGuide *guide = GetNewGuide( &src, fullPath );
                if ( guide != NULL ) {
                    DeclManager_SetGuide( guide );
                }
                continue;
            }
            if ( token.Icmp( "inlineGuide" ) == 0 ) {
                rvDeclGuide *guide = GetNewGuide( &src, fullPath );
                if ( guide != NULL ) {
                    guide->RemoveOuterBracing();
                    DeclManager_SetGuide( guide );
                }
            }
        }
    }
    
    if ( fileList != NULL ) {
        fileSystem->FreeFileList( fileList );
    }
    common->Printf( "%d loaded\n", guideTable.Num() );
    */
}

-(void)shutdownGuides {
    //guideTable.DeleteContents();
}

-(BOOL)evaluateGuide:(NSMutableString *)name source:(idLexer *)src definition:(NSMutableString *)definition error:(NSError **)error {
    idToken guideName;

    idToken_Init(&guideName);
    [definition setString:@""];

    if (![src readToken:&guideName error:error]) {
        [src warning:@"Missing guide name in '%@'", name];
        return NO;
    }
    /*
    rvDeclGuide *guide = DeclManager_FindGuide( guideName.c_str() );
    if ( !guide ) {
        src->Warning( "Guide name '%s' not found in '%s'", guideName.c_str(), name.c_str() );
        return false;
    }
    
    guide->Evaluate( src, definition );
    return true;
    */
    return NO;
}

-(BOOL)evaluateInlineGuide:(NSMutableString *)name definition:(NSMutableString *)definition error:(NSError **)error {
    NSMutableString *store = [definition mutableCopy];
    idLexer *lexer = [[idLexer alloc] initWithFlags:DECL_LEXER_FLAGS fileSystem:_workspace.fileSystem];
    const char *utf8 = store.UTF8String;
    int len = (int)strlen(utf8);

    if (![lexer loadMemory:store.UTF8String length:len name:name startLine:1 error:error]) {
        return NO;
    }
    
    idToken token;
    idToken_Init(&token);
    int defOffset = 0;
    while (![lexer endOfFile]) {
        const int inlineStart = [lexer fileOffset];
        if (![lexer readToken:&token error:error]) {
            break;
        }
        if (strcasecmp(token.text, "inlineGuide") != 0) {
            continue;
        }
        
        idToken guideName;
        idToken_Init(&guideName);
        if (![lexer readToken:&guideName error:error]) {
            return NO;
        }
        
        return NO;
        /*
        rvDeclGuide *guide = DeclManager_FindGuide( guideName.c_str() );
        if ( !guide ) {
            return false;
        }
        
        idStr expanded;
        guide->Evaluate( &lexer, expanded );
        
        const int inlineLength = lexer.GetFileOffset() - inlineStart;
        const int replaceOffset = defOffset + inlineStart;
        idStr prefix = definition.Mid( 0, replaceOffset );
        idStr suffix = definition.Mid( replaceOffset + inlineLength, definition.Length() - replaceOffset - inlineLength );
        definition = prefix + expanded + suffix;
        defOffset += expanded.Length() - inlineLength;
        */
    }
    
    return YES;
}

-(void)setInsideLoad:(BOOL)var {
    self->insideLevelLoad = var;
}

-(BOOL)insideLoad {
    return self->insideLevelLoad;
}

-(void)reload:(BOOL)force error:(NSError **)error {
    for (int i = 0; i < self->loadedFiles.count; i++) {
        //DeclManager_ShowReloadProgress( i, loadedFiles.Num(), loadedFiles[i]->fileName.c_str() );
        [loadedFiles[i] reload:force error:error];
    }
}

-(void)beginLevelLoad{
    self->insideLevelLoad = YES;
    
    // clear all the referencedThisLevel flags and purge all the data
    // so the next reference will cause a reparse
    for (int i = 0; i < DECL_MAX_TYPES; i++) {
        int    num = self->linearLists[i].count;
        for (int j = 0 ; j < num ; j++) {
            idDeclLocal *decl = linearLists[i][j];
            [decl purge];
        }
    }

    /*
    for (int i = 0; i < linearLists[DECL_MATERIAL].count; i++) {
        idDeclLocal *decl = linearLists[DECL_MATERIAL][i];
        if (decl->selfDecl != nil) {
            static_cast<idMaterial *>( decl->self )->ClearUseCount();
        }
    }*/
}

-(void)endLevelLoad{
    self->insideLevelLoad = NO;
    /*
    for (int i = 0; i < linearLists[DECL_MATERIAL].count; i++) {
        idDeclLocal *decl = linearLists[DECL_MATERIAL][i];
        if (decl->selfDecl != nil) {
            static_cast<idMaterial *>( decl->self )->ResolveUse();
        }
    }*/
}

-(void)registerDeclType:(declType_t)type typeName:(NSString *)typeName allocator:(idDeclAllocator_t)allocator {

    idDeclType *declType;
    
    if (type < DECL_MAX_TYPES && declTypes[(int)type] != nil) {
        NSLog(@"registerDeclType:typeName:allocator: type '%@' already exists", typeName);
        return;
    }

    declType = [[idDeclType alloc] initWithTypeName:typeName type:type allocator:allocator];
    
    if ((int)type + 1 > DECL_MAX_TYPES) {
        //declTypes.AssureSize( (int)type + 1, NULL );
        return;
    }
    declTypes[type] = declType;
}

-(void)startLoadingDecls {
    if (self->singleDeclFile != nil) {
        [self finishLoadingDecls];
    }
    
    NSMutableString *singleDeclFileName = [[NSMutableString alloc] init];
    DeclManager_GetSingleDeclFileName(_workspace, singleDeclFileName);
    singleDeclFile = [_workspace.fileSystem openFileRead:singleDeclFileName allowCopyFiles:YES gamedir:nil error:nil];
    if (singleDeclFile == nil) {
        NSLog(@"Could not open packed decl file '%@'", singleDeclFileName);
    }
}

-(void)finishLoadingDecls {
    if (singleDeclFile != nil) {
        [_workspace.fileSystem closeFile:singleDeclFile error:nil];
        singleDeclFile = nil;
    }
}

#pragma mark - Enumerator

/**
 * declTypes[typeIndex] — nil means invalid / unused type slot.
 * Return type: whatever you already store (id, or your type-info object).
 */
- (id)declTypeAtIndex:(int)typeIndex {
    return declTypes[typeIndex];
}

/**
 * linearLists[typeIndex] — NSArray/NSMutableArray of idDeclLocal *.
 * May later contain nil tombstones; enumerator already skips nil.
 */
- (NSArray *)linearListAtTypeIndex:(int)typeIndex {
    return linearLists[typeIndex];
}

- (id<NSFastEnumeration>)declsOfType:(declType_t)type {
    return [self declsOfType:type forceParse:NO];
}

- (id<NSFastEnumeration>)declsOfType:(declType_t)type forceParse:(BOOL)forceParse {
    return [[UDDeclEnumerator alloc] initWithManager:self
                                                 type:type
                                           forceParse:forceParse];
}

#pragma mark - Rest

-(BOOL)loadDeclsFromFile:(NSError **)error {
    if (self->singleDeclFile == nil) {
        return YES;
    }
    
    NSMutableString *singleDeclFileName = [[NSMutableString alloc] init];
    DeclManager_GetSingleDeclFileName(_workspace, singleDeclFileName);
    
    NSMutableString *countString = [[NSMutableString alloc] init];
    if (!readPackedDeclLine(self->singleDeclFile, countString, error)) {
        NSLog(@"Packed decl file '%@' ended before a section header", singleDeclFileName);
        return NO;
    }
    
    const int fileCount = [countString integerValue];
    for (int fileIndex = 0; fileIndex < fileCount; fileIndex++) {
        NSMutableString *packedFileName = [[NSMutableString alloc] init];
        NSMutableString *defaultTypeString = [[NSMutableString alloc] init];
        
        if (!readPackedDeclLine(singleDeclFile, packedFileName, error) || !readPackedDeclLine(singleDeclFile, defaultTypeString, error)) {
            NSLog(@"Packed decl file '%@' ended inside a section header", singleDeclFileName);
            return NO;
        }
        
        declType_t defaultType = (declType_t)[defaultTypeString integerValue];
        NSMutableString *extension = [[packedFileName pathExtension] mutableCopy];
        NSMutableString *folder = [[packedFileName stringByDeletingLastPathComponent] mutableCopy];
        [extension insertString:@"." atIndex:0];
        //folder.StripTrailing( '/' );
        //folder.StripTrailing( '\\' );
        
        [self findOrCreateDeclFolder:folder extension:extension defaultType:defaultType];
        idDeclFile *declFile = [self findOrCreateLoadedDeclFile:packedFileName defaultType:defaultType];
        if (![declFile loadAndParseFrom:singleDeclFile error:error]) {
            return NO;
        }
    }
    
    return YES;
}

-(BOOL)writeDeclFile:(NSError **)error {
    return [self writeDeclFileWithMode:DeclManager_GetConfiguredSingleDeclWriteMode(_workspace) error:error];
}

-(BOOL)writeDeclFileWithMode:(enum declSingleFileWriteMode_t)writeMode error:(NSError **)error {
    NSMutableString *singleDeclFileName = [[NSMutableString alloc] init];
    DeclManager_GetSingleDeclFileName(_workspace, singleDeclFileName);
    
    idFile *file = [_workspace.fileSystem openFileWrite:singleDeclFileName basePath:@"fs_savepath" error:error];
    if (file == nil) {
        NSLog(@"Could not open packed decl file '%@' for writing", singleDeclFileName);
        return NO;
    }
    
    NSMutableSet<NSNumber *> *frameworkTypes = [[NSMutableSet alloc] init];
    NSMutableSet<NSNumber *> *gameTypes = [[NSMutableSet alloc] init];
    makeDeclTypeList(frameworkTypes, declSingleFileFrameworkTypes, sizeof(declSingleFileFrameworkTypes) / sizeof(declSingleFileFrameworkTypes[0]));
    DeclManager_MakeGameDeclTypeList(gameTypes, writeMode);
    
    if (![self writeSingleDeclSection:file typesToWrite:frameworkTypes writeStubs:NO error:error]) {
        return NO;
    }
    if (![self writeSingleDeclSection:file typesToWrite:gameTypes writeStubs:NO error:error]) {
        return NO;
    }
    
    BOOL ret = [_workspace.fileSystem closeFile:file error:error];
    if (ret) {
        NSLog(@"Wrote packed decl file '%@' using %s game-type coverage", singleDeclFileName, DeclManager_GetSingleDeclWriteModeName(writeMode));
    }
    return ret;
}

-(void)flushDecls{
    for (int i = (int)loadedFiles.count - 1; i >= 0; i--) {
        for (idDeclLocal *decl = loadedFiles[i]->decls; decl; decl = decl->nextInFile) {
            [decl purge];
        }
    }
}

-(BOOL)registerDeclFolder:(NSString *)folder extension:(NSString *)extension declType:(declType_t)defaultType error:(NSError **)error {
    return [self registerDeclFolderWrapper:folder extension:extension defaultType:defaultType unique:NO nonrecursive:NO error:error];
}

-(BOOL)registerDeclFolder:(NSString *)folder extension:(NSString *)extension declType:(declType_t)defaultType unique:(BOOL)unique nonrecursive:(BOOL)norecurse error:(NSError **)error {
    idDeclFolder *declFolder = [self findOrCreateDeclFolder:folder extension:extension defaultType:defaultType];
    if (declFolder == nil) {
        return YES;
    }

    idFileList *fileList = [_workspace.fileSystem listFiles:declFolder.folder
                                                  extension:extension
                                                     sorted:YES
                                                      error:error];
    if (error && *error) {
        return NO;
    }

    if (fileList != nil) {
        NSArray<NSString *> *list = fileList.list;

        for (int fileIndex = 0; fileIndex < list.count; fileIndex++) {
            NSString *fileName = [[declFolder folder] stringByAppendingPathComponent:list[fileIndex]];
            idDeclFile *declFile = [self findOrCreateLoadedDeclFile:fileName defaultType:defaultType];
            if (![declFile loadAndParse:unique error:error]) {
                return NO;
            }
        }
        [_workspace.fileSystem freeFileList:fileList];
        fileList = nil;
    }
    
    if (norecurse) {
        return YES;
    }
    
    idFileList *folderList = [_workspace.fileSystem listFiles:folder extension:@"/" sorted:YES error:error];

    if (folderList != nil) {
        NSArray<NSString *> *list = folderList.list;

        for (int folderIndex = 0; folderIndex < list.count; folderIndex++) {
            NSString *childFolder = list[folderIndex];
            
            if (childFolder.length == 0 || [childFolder characterAtIndex:0] == '.') {
                continue;
            }
            
            NSString *childPath = [folder stringByAppendingPathComponent:childFolder];
            BOOL ret = [self registerDeclFolder:childPath extension:extension declType:defaultType unique:unique nonrecursive:NO error:error];
            if (!ret) {
                return NO;
            }
        }
        [_workspace.fileSystem freeFileList:folderList];
        folderList = nil;
    }

    return YES;
}

-(BOOL)registerDeclFolderWrapper:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType unique:(BOOL)unique nonrecursive:(BOOL)norecurse error:(NSError **)error {
    NSTimeInterval start = [[NSProcessInfo processInfo] systemUptime];
    
    BOOL ret = [self registerDeclFolder:folder
                              extension:extension
                               declType:defaultType
                                 unique:unique
                           nonrecursive:norecurse
                                  error:error];

    NSTimeInterval end = [[NSProcessInfo processInfo] systemUptime];
    int elapsedMs = (int)((end - start) * 1000.0);

    NSLog(@"%dms to load %dk of %@\n",
          elapsedMs,
          ([self totalTextMemory:defaultType] + 1023) / 1024,
          [self declTypeName:defaultType]);
    
    return ret;
}

-(BOOL)registerDeclFolderWrapper:(NSString *)folder
                       extension:(NSString *)extension
                     defaultType:(declType_t)defaultType
                          unique:(BOOL)unique
                           error:(NSError **)error {
    return [self registerDeclFolderWrapper:folder
                                 extension:extension
                               defaultType:defaultType
                                    unique:unique
                              nonrecursive:NO
                                     error:error];
}

-(BOOL)registerDeclFolderWrapper:(NSString *)folder
                       extension:(NSString *)extension
                     defaultType:(declType_t)defaultType
                    nonrecursive:(BOOL)norecurse
                           error:(NSError **)error { // unique=NO
    return [self registerDeclFolderWrapper:folder
                                 extension:extension
                               defaultType:defaultType
                                    unique:NO
                              nonrecursive:norecurse
                                    error:error];
}

-(BOOL)registerDeclFolderWrapper:(NSString *)folder
                       extension:(NSString *)extension
                     defaultType:(declType_t)defaultType
                           error:(NSError **)error {
    return [self registerDeclFolderWrapper:folder
                                 extension:extension
                               defaultType:defaultType
                                    unique:NO
                              nonrecursive:NO
                                     error:error];
}

-(idDeclFile *)findLoadedDeclFile:(NSString *)fileName {
    for (int i = 0; i < loadedFiles.count; i++) {
        idDeclFile *file = [loadedFiles objectAtIndex:i];

        if ([file->fileName caseInsensitiveCompare:fileName] == NSOrderedSame) {
            return file;
        }
    }
    return nil;
}

-(idDeclFile *)findOrCreateLoadedDeclFile:(NSString *)fileName defaultType:(declType_t)defaultType {
    idDeclFile *declFile = [self findLoadedDeclFile:fileName];
    if (declFile != nil) {
        return declFile;
    }
    
    declFile = [[idDeclFile alloc] initWithFileName:fileName defaultType:defaultType manager:self];
    [loadedFiles addObject:declFile];
    return declFile;
}

-(idDeclFolder *)findOrCreateDeclFolder:(NSString *)folder extension:(NSString *)extension defaultType:(declType_t)defaultType {
    for (int i = 0; i < declFolders.count; i++) {
        idDeclFolder *declFolder = [declFolders objectAtIndex:i];

        if ([declFolder.folder caseInsensitiveCompare:folder] == NSOrderedSame
            && [declFolder.extension caseInsensitiveCompare:extension] == NSOrderedSame) {
            return declFolder;
        }
    }
    
    idDeclFolder *declFolder = [[idDeclFolder alloc] initWithFolder:folder extension:extension defaultType:defaultType];
    [declFolders addObject:declFolder];
    return declFolder;
}

-(BOOL)typeListContains:(NSSet<NSNumber *> *)types type:(declType_t)type {
    return [types containsObject:@(type)];
}

-(int)totalTextMemory:(declType_t)type {
    const int typeIndex = (int)type;
    if (typeIndex < 0 || typeIndex >= [self numDeclTypes] || declTypes[typeIndex] == nil) {
        //common->FatalError( "idDeclManager::GetTotalTextMemory: bad type: %i", typeIndex );
        return 0; // FIXME: throw, no return here
    }
    
    int totalTextMemory = 0;
    const int numDecls = [self numDecls:type];
    for (int i = 0; i < numDecls; i++) {
        const idDecl *decl = [self declByIndex:i type:type forceParse:NO error:nil];
        totalTextMemory += [decl compressedLength];
    }
    return totalTextMemory;
}

-(int)numWritableDecls:(idDeclFile *)declFile typesToWrite:(NSSet<NSNumber *> *)typesToWrite writeStubs:(BOOL)writeStubs {
    int count = 0;
    for (idDeclLocal *decl = declFile->decls; decl; decl = decl->nextInFile) {
        if ([self typeListContains:typesToWrite type:decl->type] && (decl->declState == DS_PARSED || writeStubs)) {
            count++;
        }
    }
    return count;
}

-(void)buildPackedDeclText:(idDeclLocal *)decl into:(NSMutableString *)declText buffer:(NSMutableData *)buffer {
    [declText setString:@""];
    [declText appendString:[self->declTypes[(int)decl->type] typeName]];
    [declText appendString:@" "];
    [declText appendString:[decl name]];
    [declText appendString:@"\n"];
    
    if (decl->declState == DS_PARSED && decl->textSource != nil) {
        const int textLength = [decl textLength];
        buffer.length = textLength;
        [decl text:buffer];
        NSString *str = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
        if (str) {
            [declText appendString:str];
        } else {
            // TODO: barf. invalid string.
        }
        return;
    }

    [declText appendString:@"\n{ STUB: "];
    [declText appendFormat:@"%d %d", decl->sourceTextOffset, decl->sourceTextLength];
    [declText appendString:@" }"];
}

-(BOOL)writeDecls:(idFile *)file declFile:(idDeclFile *)declFile typesToWrite:(NSSet<NSNumber *> *)typesToWrite writeStubs:(BOOL)writeStubs error:(NSError **)error {
    const int writableDecls = [self numWritableDecls:declFile typesToWrite:typesToWrite writeStubs:writeStubs];
    if (writableDecls <= 0) {
        return NO;
    }
    
    [file printf:@"%@\n", declFile->fileName];
    [file printf:@"%d\n", (int)declFile->defaultType];
    [file printf:@"%d\n", writableDecls];

    NSMutableString *declText = [[NSMutableString alloc] init];
    NSMutableData *buf = [[NSMutableData alloc] init];

    for (idDeclLocal *decl = declFile->decls; decl; decl = decl->nextInFile) {
        if (![self typeListContains:typesToWrite type:decl->type]) {
            continue;
        }
        if (decl->declState != DS_PARSED && !writeStubs) {
            continue;
        }
        
        [self buildPackedDeclText:decl into:declText buffer:buf];
        NSUInteger linearIndex = [linearLists[(int)decl->type] indexOfObject:decl];
        if (linearIndex == NSNotFound) {
            linearIndex = decl->index;
        }
        [file printf:@"%d\n", linearIndex];
        [file printf:@"%d\n", declText.length + 1];
        [file printf:@"%@", declText]; // FIXME: should we just write it out verbatim as bytes?
        [file write:@"\n" length:1 error:error];
    }
    
    return YES;
}

-(BOOL)writeSingleDeclSection:(idFile *)file typesToWrite:(NSSet<NSNumber *> *)typesToWrite writeStubs:(BOOL)writeStubs error:(NSError **)error {
    int writableFiles = 0;
    for (int i = 0; i < self->loadedFiles.count; i++) {
        if ([self numWritableDecls:[self->loadedFiles objectAtIndex:i] typesToWrite:typesToWrite writeStubs:writeStubs] > 0) {
            writableFiles++;
        }
    }
    
    [file printf:@"%d\n", writableFiles];
    for (int i = 0; i < self->loadedFiles.count; i++) {
        if (![self writeDecls:file declFile:[loadedFiles objectAtIndex:i] typesToWrite:typesToWrite writeStubs:writeStubs error:error]) {
            return NO;
        }
    }
    
    return YES;
}

-(void)checkDecls {
    for (int i = 0; i < loadedFiles.count; i++) {
        for (idDeclLocal *decl = [loadedFiles objectAtIndex:i]->decls; decl; decl = decl->nextInFile) {
            if (decl->declState != DS_PARSED) {
                [decl parseLocal:NO error:nil];
            }
        }
    }
}

-(void)deleteLocalDecl:(idDeclLocal *)decl {
    if (decl == nil) {
        return;
    }
    if (decl->selfDecl != nil) {
        [decl->selfDecl freeData];
        decl->selfDecl = nil; //delete decl->self;
    }
    if (decl->textSource != nil) {
        //Mem_Free( decl->textSource );
        decl->textSource = nil;
    }
    //delete decl;
}

-(int)checksum {
    int i, j, total, num;
    int *checksumData;
    
    // get the total number of decls
    total = 0;
    for (i = 0; i < DECL_MAX_TYPES; i++) {
        total += linearLists[i].count;
    }
    
    const int checksumCapacity = total > 0 ? total * 2 : 2;
    checksumData = (int *)alloca(checksumCapacity * sizeof(int)); // FIXME: _alloca16?
    
    total = 0;
    for (i = 0; i < DECL_MAX_TYPES; i++) {
        declType_t type = (declType_t)i;
        
        // FIXME: not particularly pretty but PDAs and associated decls are localized and should not be checksummed
        if (type == DECL_PDA || type == DECL_VIDEO || type == DECL_AUDIO || type == DECL_EMAIL) {
            continue;
        }
        
        num = (int)linearLists[i].count;
        for (j = 0; j < num; j++) {
            idDeclLocal *decl = [linearLists[i] objectAtIndex:j];
            
            if (decl->sourceFile == self->implicitDecls) {
                continue;
            }
            
            checksumData[total*2+0] = total;
            checksumData[total*2+1] = decl->checksum;
            total++;
        }
    }
    
    LittleRevBytes(checksumData, sizeof(int), total * 2);
    return MD5_BlockChecksum(checksumData, total * 2 * sizeof(int));
}

-(int)numDeclTypes {
    for (int i = DECL_MAX_TYPES - 1; i >= 0; i--) {
        if (declTypes[i] != nil)
            return i + 1;
    }
    return 0;
}

-(NSString *)declNameFromType:(declType_t)type {
    int typeIndex = (int)type;
    
    if (typeIndex < 0 || typeIndex >= [self numDeclTypes] || declTypes[typeIndex] == nil) {
        //common->FatalError( "idDeclManager::GetDeclNameFromType: bad type: %i", typeIndex );
        return @"bad type"; // FIXME: error out here
    }
    return [declTypes[typeIndex] typeName];
}

-(declType_t)declTypeFromName:(NSString *)typeName {
    int i;
    
    for (i = 0; i < [self numDeclTypes]; i++) {
        if (declTypes[i] && [declTypes[i].typeName caseInsensitiveCompare:typeName] == NSOrderedSame) {
            return (declType_t)declTypes[i].type;
        }
    }
    return DECL_MAX_TYPES;
}

-(idDecl *)findType:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault noCaching:(BOOL)noCaching error:(NSError **)error {
    idDeclLocal *decl;
    
    if (!name || !name.length) {
        name = @"_emptyName";
        NSLog(@"findType:name:makeDefault:noCaching:error: empty %@ name", [[self declType:(int)type] typeName]);
    }
    
    decl = [self findTypeWithoutParsing:type name:name makeDefault:makeDefault];
    if (!decl) {
        return nil;
    }
    
    [decl allocateSelf];
    
    // if it hasn't been parsed yet, parse it now
    if (decl->declState == DS_UNPARSED) {
        [decl parseLocal:noCaching error:error];
        if (noCaching) {
            [decl->selfDecl list];
        }
    }
    
    // mark it as referenced
    decl->referencedThisLevel = YES;
    decl->everReferenced = YES;
    if (insideLevelLoad) {
        decl->parsedOutsideLevelLoad = NO;
    }
    /*
    if (type == DECL_MATERIAL && insideLevelLoad) {
        idMaterial *material = static_cast<idMaterial *>( decl->self );
        material->AddLevelLoadReference();
    }
    */
    
    return decl->selfDecl;
}

-(idDecl *)findType:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error {
    return [self findType:type name:name makeDefault:makeDefault noCaching:NO error:error];
}

-(idDecl *)findType:(declType_t)type name:(NSString *)name noCaching:(BOOL)noCaching error:(NSError **)error {
    return [self findType:type name:name makeDefault:YES noCaching:noCaching error:error];
}

-(idDecl *)findType:(declType_t)type name:(NSString *)name error:(NSError **)error {
    return [self findType:type name:name makeDefault:YES noCaching:NO error:error];
}

-(idDecl *)findDeclWithoutParsing:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault {
    idDeclLocal* decl;
    decl = [self findTypeWithoutParsing:type name:name makeDefault:makeDefault];
    if (decl) {
        return decl->selfDecl;
    }
    return nil;
}

-(idDecl *)findDeclWithoutParsing:(declType_t)type name:(NSString *)name {
    return [self findDeclWithoutParsing:type name:name makeDefault:YES];
}

-(void)reloadFile:(NSString *)filename force:(BOOL)force {
    for (int i = 0; i < loadedFiles.count; i++) {
        idDeclFile *declFile = [loadedFiles objectAtIndex:i];
        
        if ([declFile->fileName caseInsensitiveCompare:filename] == NSOrderedSame) {
            checksum ^= declFile->checksum;
            [loadedFiles[i] reload:force error:nil];
            checksum ^= declFile->checksum;
        }
    }
}

-(int)numDecls:(declType_t)type {
    int typeIndex = (int)type;
    
    if (typeIndex < 0 || typeIndex >= [self numDeclTypes] || declTypes[typeIndex] == nil) {
        // TODO: throw here
        //common->FatalError("idDeclManager::GetNumDecls: bad type: %i", typeIndex);
        return 0;
    }
    return (int)linearLists[typeIndex].count;
}

-(idDecl *)declByName:(NSString *)name type:(declType_t)type forceParse:(BOOL)forceParse error:(NSError **)error {
    int typeIndex = (int)type;
    NSNumber *i = nil;
    idDeclLocal *decl;

    if (typeIndex < 0 || typeIndex >= [self numDeclTypes] || declTypes[typeIndex] == nil) {
        //common->FatalError("idDeclManager::DeclByIndex: bad type: %i", typeIndex);
        return nil; // TODO: throw
    }
    
    NSMutableString *lookupName = [idDeclManager makeCanonicalName:name];

    // make sure it already exists
    i = self->hashTables[typeIndex][lookupName];

    if(!i)
        return nil;

    decl = [self->linearLists[typeIndex] objectAtIndex: [i integerValue]];
    if (!decl)
        return nil;

    [decl allocateSelf];
    
    if (forceParse && decl->declState == DS_UNPARSED) {
        if (![decl parseLocal:NO error:error]) {
            return nil;
        }
    }
    
    return decl->selfDecl;
}

-(idDecl *)declByName:(NSString *)name type:(declType_t)type error:(NSError **)error {
    return [self declByName:name type:type forceParse:YES error:error];
}

-(idDecl *)declByIndex:(int)index type:(declType_t)type forceParse:(BOOL)forceParse error:(NSError **)error {
    int typeIndex = (int)type;
    
    if (typeIndex < 0 || typeIndex >= [self numDeclTypes] || declTypes[typeIndex] == nil) {
        //common->FatalError("idDeclManager::DeclByIndex: bad type: %i", typeIndex);
        return nil; // TODO: throw
    }
    if (index < 0 || index >= linearLists[typeIndex].count) {
        //common->Error("idDeclManager::DeclByIndex: out of range for type %d (index desired: %d, max: %d)",
                      //typeIndex, index, linearLists[typeIndex].Num());
        return nil; // TODO: throw
    }
    idDeclLocal *decl = [linearLists[typeIndex] objectAtIndex:index];
    
    [decl allocateSelf];
    
    if (forceParse && decl->declState == DS_UNPARSED) {
        if (![decl parseLocal:NO error:error]) {
            return nil;
        }
    }
    
    return decl->selfDecl;
}

-(idDecl *)declByIndex:(int)index type:(declType_t)type error:(NSError **)error {
    return [self declByIndex:index type:type forceParse:YES error:error];
}

#if 0

-(void)listType:(declType_t)type {
    bool all, ever;
    
    if ( !idStr::Icmp( args.Argv( 1 ), "all" ) ) {
        all = true;
    } else {
        all = false;
    }
    if ( !idStr::Icmp( args.Argv( 1 ), "ever" ) ) {
        ever = true;
    } else {
        ever = false;
    }
    
    common->Printf( "--------------------\n" );
    int printed = 0;
    int    count = linearLists[ (int)type ].Num();
    for ( int i = 0 ; i < count ; i++ ) {
        idDeclLocal *decl = linearLists[ (int)type ][ i ];
        
        if ( !all && decl->declState == DS_UNPARSED ) {
            continue;
        }
        
        if ( !all && !ever && !decl->referencedThisLevel ) {
            continue;
        }
        
        if ( decl->referencedThisLevel ) {
            common->Printf( "*" );
        } else if ( decl->everReferenced ) {
            common->Printf( "." );
        } else {
            common->Printf( " " );
        }
        if ( decl->declState == DS_DEFAULTED ) {
            common->Printf( "D" );
        } else {
            common->Printf( " " );
        }
        common->Printf( "%4i: ", decl->index );
        printed++;
        if ( decl->declState == DS_UNPARSED ) {
            // doesn't have any type specific data yet
            common->Printf( "%s\n", decl->GetName() );
        } else {
            decl->self->List();
        }
    }
    
    common->Printf( "--------------------\n" );
    common->Printf( "%i of %i %s\n", printed, count, declTypes[type]->typeName.c_str() );
}

/*
 ===================
 idDeclManagerLocal::PrintType
 ===================
 */
void idDeclManagerLocal::PrintType( const idCmdArgs &args, declType_t type ) {
    // individual decl types may use additional command parameters
    if ( args.Argc() < 2 ) {
        common->Printf( "USAGE: Print<decl type> <decl name> [type specific parms]\n" );
        return;
    }
    
    // look it up, skipping the public path so it won't parse or reference
    idDeclLocal *decl = FindTypeWithoutParsing( type, args.Argv( 1 ), false );
    if ( !decl ) {
        common->Printf( "%s '%s' not found.\n", declTypes[ type ]->typeName.c_str(), args.Argv( 1 ) );
        return;
    }
    
    // print information common to all decls
    common->Printf( "%s %s:\n", declTypes[ type ]->typeName.c_str(), decl->name.c_str() );
    common->Printf( "source: %s:%i\n", decl->sourceFile->fileName.c_str(), decl->sourceLine );
    common->Printf( "----------\n" );
    if ( decl->textSource != NULL ) {
        char *declText = (char *)_alloca( decl->textLength + 1 );
        decl->GetText( declText );
        common->Printf( "%s\n", declText );
    } else {
        common->Printf( "NO SOURCE\n" );
    }
    common->Printf( "----------\n" );
    switch( decl->declState ) {
        case DS_UNPARSED:
            common->Printf( "Unparsed.\n" );
            break;
        case DS_DEFAULTED:
            common->Printf( "<DEFAULTED>\n" );
            break;
        case DS_PARSED:
            common->Printf( "Parsed.\n" );
            break;
    }
    
    if ( decl->referencedThisLevel ) {
        common->Printf( "Currently referenced this level.\n" );
    } else if ( decl->everReferenced ) {
        common->Printf( "Referenced in a previous level.\n" );
    } else {
        common->Printf( "Never referenced.\n" );
    }
    
    // allow type-specific data to be printed
    if ( decl->self != NULL ) {
        decl->self->Print();
    }
}
#endif

-(idDecl *)createNewDecl:(declType_t)type name:(NSString *)name fileName:(NSString *)_fileName {
    int typeIndex = (int)type;
    int i;
    
    if (typeIndex < 0 || typeIndex >= [self numDeclTypes] || declTypes[typeIndex] == nil) {
        //common->FatalError("idDeclManager::CreateNewDecl: bad type: %i", typeIndex);
        return nil; // TODO: throw
    }

    NSMutableString *lookupName = [idDeclManager makeCanonicalName:name];

    NSMutableString *fileName = [[NSMutableString alloc] init];

    if (_fileName != nil) {
        [fileName setString:_fileName];
    }
    [fileName replaceOccurrencesOfString:@"\\" withString:@"/" options:NSLiteralSearch range:NSMakeRange(0, fileName.length)];
    
    // see if it already exists
    idDeclLocal *existingDecl = self->hashTables[typeIndex][lookupName];
    
    if (existingDecl) {
        [existingDecl allocateSelf];
        return existingDecl->selfDecl;
    }

    idDeclFile *sourceFile;
    
    // find existing source file or create a new one
    for (i = 0; i < loadedFiles.count; i++) {
        if ([loadedFiles[i]->fileName caseInsensitiveCompare:fileName] == NSOrderedSame) {
            break;
        }
    }
    if (i < loadedFiles.count) {
        sourceFile = loadedFiles[i];
    } else {
        sourceFile = [[idDeclFile alloc] initWithFileName:fileName defaultType:type manager:self];
        [loadedFiles addObject:sourceFile];
    }
    
    idDeclLocal *decl = [[idDeclLocal alloc] init];
    decl->declManager = self;
    decl->name = lookupName;
    decl->type = type;
    decl->declState = DS_UNPARSED;
    [decl allocateSelf];
    NSMutableString *header = [[declTypes[typeIndex] typeName] mutableCopy];
    NSMutableString *defaultText = [[NSMutableString alloc] init];
    NSString *defaultDefinition = [decl->selfDecl defaultDefinition];
    if (defaultDefinition != nil) {
        defaultText = [defaultDefinition mutableCopy];
    }
    
    NSString *declText = [NSString stringWithFormat:@"%@ %@ %@", header, lookupName, defaultText];

    [decl setTextLocal:declText];
    decl->sourceFile = sourceFile;
    decl->sourceTextOffset = sourceFile->fileSize;
    decl->sourceTextLength = 0;
    decl->sourceLine = sourceFile->numLines;
    
    [decl parseLocal:NO error:nil];
    
    // add this decl to the source file list
    decl->nextInFile = sourceFile->decls;
    sourceFile->decls = decl;
    
    // add it to the hash table and linear list
    decl->index = (int)linearLists[typeIndex].count;
    [linearLists[typeIndex] addObject:decl];
    hashTables[typeIndex][lookupName] = @(decl->index);
    
    return decl->selfDecl;
}

-(BOOL)renameDecl:(declType_t)type fromName:(NSString *)oldName toName:(NSString *)newName {
    
    NSMutableString *lookupOldName = [idDeclManager makeCanonicalName:oldName];
    NSMutableString *lookupNewName = [idDeclManager makeCanonicalName:newName];
    
    idDeclLocal    *decl = nil;
    NSNumber *i = nil;
    
    // make sure it already exists
    int typeIndex = (int)type;
    i = self->hashTables[typeIndex][lookupOldName];

    if(!i)
        return NO;

    decl = [self->linearLists[typeIndex] objectAtIndex: [i integerValue]];
    if (!decl)
        return NO;

    //if ( !hashTables[(int)type].Get( canonicalOldName, &declPtr ) )
    //    return false;
    
    //decl = *declPtr;
    
    //Change the name
    decl->name = lookupNewName;

    // add it to the hash table
    [self->hashTables[typeIndex] setValue:@(decl->index) forKey:lookupNewName];
    
    //Remove the old hash item
    [self->hashTables[typeIndex] removeObjectForKey:lookupOldName];
    
    return YES;
}

-(void)mediaPrint:(NSString *)fmt, ... {
    if (!_workspace.decl_show) {
        return;
    }

    NSMutableString *message = [NSMutableString string];
    for (int i = 0; i < indent; i++) {
        [message appendString:@"    "];
    }

    va_list args;
    va_start(args, fmt);
    NSString *formattedString = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    [message appendString:formattedString];

    NSLog(@"%@", message);
}

-(void)writePrecacheCommands:(idFile *)f {
    int numDeclTypes = [self numDeclTypes];

    for (int i = 0; i < numDeclTypes; i++) {
        int num;
        
        if (declTypes[i] == nil) {
            continue;
        }
        
        num = linearLists[i].count;
        
        for (int j = 0 ; j < num ; j++) {
            idDeclLocal *decl = linearLists[i][j];
            
            if (!decl->referencedThisLevel) {
                continue;
            }
            
            NSString *command = [NSString stringWithFormat:@"touch %@ %@\n", [declTypes[i] typeName], [decl name]];
            [f printf:@"%@", command];
        }
    }
}

/********************************************************************/

-(idDeclMaterial *)findMaterial:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error {
    return (idDeclMaterial *)[self findType:DECL_MATERIAL name:name makeDefault:makeDefault error:error];
}

-(idDeclMaterial *)findMaterial:(NSString *)name error:(NSError **)error {
    return [self findMaterial:name makeDefault:YES error:error];
}

-(idDeclMaterial *)materialByIndex:(int)index forceParse:(BOOL)forceParse error:(NSError **)error {
    idDeclMaterial *material = (idDeclMaterial *)[self declByIndex:index type:DECL_MATERIAL forceParse:forceParse error:error];
    /*
    if (material != nil && insideLevelLoad) {
        const_cast<idMaterial *>( material )->AddLevelLoadReference();
    }*/
    return material;
}

-(idDeclMaterial *)materialByIndex:(int)index error:(NSError **)error {
    return [self materialByIndex:index forceParse:YES error:error];
}

/********************************************************************/

-(idDeclSkin *)findSkin:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error {
    return (idDeclSkin *)[self findType:DECL_SKIN name:name makeDefault:makeDefault error:error];
}

-(idDeclSkin *)findSkin:(NSString *)name error:(NSError **)error {
    return [self findSkin:name makeDefault:YES error:error];
}

-(idDeclSkin *)skinByIndex:(int)index forceParse:(BOOL)forceParse error:(NSError **)error {
    return (idDeclSkin *)[self declByIndex:index type:DECL_SKIN forceParse:forceParse error:error];
}

-(idDeclSkin *)skinByIndex:(int)index error:(NSError **)error {
    return [self skinByIndex:index forceParse:YES error:error];
}

/********************************************************************/
#if 0
const idSoundShader *idDeclManagerLocal::FindSound( const char *name, bool makeDefault ) {
    return static_cast<const idSoundShader *>( FindType( DECL_SOUND, name, makeDefault ) );
}

const idSoundShader *idDeclManagerLocal::SoundByIndex( int index, bool forceParse ) {
    return static_cast<const idSoundShader *>( DeclByIndex( DECL_SOUND, index, forceParse ) );
}

// RAVEN BEGIN
// jscott: for new Raven decls
static const float DECL_MSEC_TO_SEC = 0.001f;

const rvDeclMatType* idDeclManagerLocal::FindMaterialType(const char* name, bool makeDefault) {
    return static_cast<const rvDeclMatType*>(FindType(DECL_MATERIALTYPE, name, makeDefault));
}

const rvDeclLipSync* idDeclManagerLocal::FindLipSync(const char* name, bool makeDefault) {
    return static_cast<const rvDeclLipSync*>(FindType(DECL_LIPSYNC, name, makeDefault));
}

const rvDeclPlayback* idDeclManagerLocal::FindPlayback(const char* name, bool makeDefault) {
    return static_cast<const rvDeclPlayback*>(FindType(DECL_PLAYBACK, name, makeDefault));
}
const rvDeclEffect* idDeclManagerLocal::FindEffect(const char* name, bool makeDefault) {
    return (const rvDeclEffect*)FindType(DECL_EFFECT, name, makeDefault);
}
#endif
-(idDeclTable *)findTable:(NSString *)name makeDefault:(BOOL)makeDefault error:(NSError **)error {
    return (idDeclTable *)[self findType:DECL_TABLE name:name makeDefault:makeDefault error:error];
}

-(idDeclTable *)findTable:(NSString *)name error:(NSError **)error {
    return [self findTable:name makeDefault:YES error:error];
}

#if 0
const rvDeclMatType* idDeclManagerLocal::MaterialTypeByIndex(int index, bool forceParse) {
    return static_cast<const rvDeclMatType*>(DeclByIndex(DECL_MATERIALTYPE, index, forceParse));
}

const rvDeclLipSync* idDeclManagerLocal::LipSyncByIndex(int index, bool forceParse) {
    return static_cast<const rvDeclLipSync*>(DeclByIndex(DECL_LIPSYNC, index, forceParse));
}

const rvDeclPlayback* idDeclManagerLocal::PlaybackByIndex(int index, bool forceParse) {
    return static_cast<const rvDeclPlayback*>(DeclByIndex(DECL_PLAYBACK, index, forceParse));
}

void idDeclManagerLocal::StartPlaybackRecord(rvDeclPlayback* playback) {
    if (playback == NULL) {
        return;
    }
    playback->Start();
}

bool idDeclManagerLocal::SetPlaybackData(rvDeclPlayback* playback, int now, int control, rvDeclPlaybackData* pbd) {
    if (playback == NULL) {
        return false;
    }
    return playback->SetCurrentData(now * DECL_MSEC_TO_SEC, control, pbd);
}

bool idDeclManagerLocal::GetPlaybackData(const rvDeclPlayback* playback, int control, int now, int last, rvDeclPlaybackData* pbd) {
    if (playback == NULL) {
        return true;
    }
    return playback->GetCurrentData(control, now * DECL_MSEC_TO_SEC, last * DECL_MSEC_TO_SEC, pbd);
}

bool idDeclManagerLocal::FinishPlayback(rvDeclPlayback* playback) {
    if (playback == NULL) {
        return false;
    }
    return playback->Finish(-1.0f);
}
#endif

-(NSString *)newName:(declType_t)type base:(NSString *)base {
    NSMutableString *name = [[NSMutableString alloc] init];
    for (int suffix = 1; suffix < 1024; suffix++) {
        [name setString:base];
        [name appendFormat:@"%d", suffix];
        if ([self findTypeWithoutParsing:type name:name makeDefault:NO] == nil) {
            return name;
        }
    }
    return @"*unknown*";
}

-(NSString *)declTypeName:(declType_t)type {
    return [self declNameFromType:type];
}

-(size_t)listDeclSummary {
    int totalDecls = 0;
    size_t totalStructBytes = 0;
    int numDeclTypes = [self numDeclTypes];
    
    for (int typeIndex = 0; typeIndex < numDeclTypes; typeIndex++) {
        if (declTypes[typeIndex] == nil) {
            continue;
        }
        
        totalDecls += linearLists[typeIndex].count;
        for (int declIndex = 0; declIndex < linearLists[typeIndex].count; declIndex++) {
            idDeclLocal *decl = linearLists[typeIndex][declIndex];
            totalStructBytes += [decl size];
            if (decl->selfDecl != nil) {
                totalStructBytes += [decl->selfDecl size];
            }
        }
    }
    
    NSLog(@"Decls           - %dK in %d decl structs", (int)(totalStructBytes >> 10), totalDecls);
    return totalStructBytes >> 10;
}

-(void)removeDeclFile:(NSString *)file {
    for (int i = 0; i < loadedFiles.count; i++) {
        if ([loadedFiles[i]->fileName caseInsensitiveCompare:file] != NSOrderedSame) {
            continue;
        }
        [loadedFiles removeObjectAtIndex:i];
        return;
    }
}

-(BOOL)validate:(declType_t)type index:(int)iIndex reportTo:(NSMutableString *)strReportTo {
    idDecl *decl = [self declByIndex:iIndex type:type forceParse:NO error:nil];

    if (decl == nil) {
        [strReportTo appendFormat:@"Invalid decl index %d for type %@\n", iIndex, [self declNameFromType:type]];
        return false;
    }
    
    NSMutableData *declText = [[NSMutableData alloc] initWithLength:[decl textLength]];
    [decl text:declText];

    /*
    struct declValidationToolState_t {
        declValidationToolState_t() : oldEditors( com_editors ) {
            com_editors |= EDITOR_DECL | EDITOR_DECL_VALIDATING;
        }
        ~declValidationToolState_t() {
            com_editors = oldEditors;
        }
        int oldEditors;
    } validationToolState;
    */
    
    return [decl validate:declText reportTo:strReportTo];
}

-(idDecl *)allocateDecl:(declType_t)type {
    const int typeIndex = (int)type;
    if (typeIndex < 0 || typeIndex >= [self numDeclTypes] || declTypes[typeIndex] == nil) {
        //common->FatalError("idDeclManager::AllocateDecl: bad type: %i", typeIndex);
        return nil; // TODO: throw
    }
    
    idDeclLocal *declBase = [[idDeclLocal alloc] init];
    declBase->declManager = self;
    declBase->selfDecl = nil;
    declBase->type = type;
    declBase->sourceFile = self->implicitDecls;
    declBase->parsedOutsideLevelLoad = !insideLevelLoad;
    
    idDecl *decl = [declTypes[typeIndex] allocator]();
    decl.declManager = self;
    [decl setBase:declBase];
    declBase->selfDecl = decl;
    return decl;
}

#if 0
/*
 ===================
 idDeclManagerLocal::GetMaterialTypeArray
 
 Interface wrapper so the renderer module reaches the material-type decl data
 across the DLL boundary (Phase B8).
 ===================
 */
byte *idDeclManagerLocal::GetMaterialTypeArray( const char *image, int &width, int &height ) {
    return MT_GetMaterialTypeArray( idStr( image ), width, height );
}

const rvDeclEffect* idDeclManagerLocal::EffectByIndex(int index, bool forceParse) {
    return (const rvDeclEffect*)DeclByIndex(DECL_EFFECT, index, forceParse);
}
#endif
-(idDeclTable *)tableByIndex:(int)index forceParse:(BOOL)forceParse error:(NSError **)error {
    idDeclTable *table = (idDeclTable *)[self declByIndex:index type:DECL_TABLE forceParse:forceParse error:error];
    return table;
}

-(idDeclTable *)tableByIndex:(int)index error:(NSError **)error {
    return [self tableByIndex:index forceParse:YES error:error];
}
// RAVEN END

+(NSMutableString *)makeCanonicalName:(NSString *)name {
    if (!name || name.length == 0) {
        return [NSMutableString string];
    }
    
    NSMutableString *canonical = [[name lowercaseString] mutableCopy];
    
    [canonical replaceOccurrencesOfString:@"\\"
                               withString:@"/"
                                  options:0
                                    range:NSMakeRange(0, canonical.length)];
    
    NSRange lastDotRange = [canonical rangeOfString:@"." options:NSBackwardsSearch];
    if (lastDotRange.location != NSNotFound) {
        NSRange extensionRange = NSMakeRange(lastDotRange.location, canonical.length - lastDotRange.location);
        [canonical deleteCharactersInRange:extensionRange];
    }
    
    return canonical;
}

-(void)listAllDecls_f {
    int numDeclTypes = [self numDeclTypes];

    for (int typeIndex = 0; typeIndex < numDeclTypes; typeIndex++) {
        idDeclType *declType = declTypes[typeIndex];
        if (declType == nil) {
            continue;
        }
        
        NSLog(@"Starting %@\n----\n", declType.typeName);
        for (int declIndex = 0; declIndex < linearLists[typeIndex].count; declIndex++) {
            NSLog(@"%@\n", linearLists[typeIndex][declIndex].name);
        }
        NSLog(@"----\n");
    }
}

-(void)listDecls_f {
    int        i, j;
    int        totalDecls = 0;
    int        totalText = 0;
    int        totalStructs = 0;
    int        numDeclTypes;
    
    numDeclTypes = [self numDeclTypes];
    for (i = 0; i < numDeclTypes; i++) {
        int size, num;
        
        if (declTypes[i] == nil) {
            continue;
        }
        
        num = linearLists[i].count;
        totalDecls += num;
        
        size = 0;
        for (j = 0; j < num; j++) {
            size += linearLists[i][j].size;
            if (linearLists[i][j]->selfDecl != nil) {
                size += linearLists[i][j]->selfDecl.size;
            }
        }
        totalStructs += size;
        
        NSLog(@"%4ik %4i %@\n", size >> 10, num, declTypes[i].typeName);
    }
    
    for (i = 0 ; i < loadedFiles.count; i++) {
        idDeclFile    *df = loadedFiles[i];
        totalText += df->fileSize;
    }
    
    NSLog(@"%i total decls is %i decl files\n", totalDecls, (int)loadedFiles.count);
    NSLog(@"%iKB in text, %iKB in structures\n", totalText >> 10, totalStructs >> 10);
}

-(void)reloadDecls_f:(NSString *)parm {
    bool    force;
    
    //[[idFileSystem sharedFileSystem] setIsFileLoadingAllowed:YES];
    [self parseGuides];
    
    if ([parm caseInsensitiveCompare:@"all"] == NSOrderedSame) {
        force = YES;
        NSLog(@"reloading all decl files:\n");
    } else {
        force = NO;
        NSLog(@"reloading changed decl files:\n");
    }
    
    //soundSystem->SetMute( true );

    [self reload:force error:nil];
    
    //soundSystem->SetMute( false );
    //[[idFileSystem sharedFileSystem] setIsFileLoadingAllowed:NO];
}

-(void)reloadFile_f:(NSString *)fileName {
    if (fileName == nil || fileName.length == 0) {
        //NSLog(@"usage: reloadFile <fileName>\n");
        return;
    }
    
    //[[idFileSystem sharedFileSystem] setIsFileLoadingAllowed:YES];
    [self parseGuides];
    
    //soundSystem->SetMute( true );
    [self reloadFile:fileName force:YES];
    //soundSystem->SetMute( false );
    //[[idFileSystem sharedFileSystem] setIsFileLoadingAllowed:NO];
}
#if 0
/*
 ===================
 idDeclManagerLocal::ResaveDecl_f
 ===================
 */
static void DeclManager_PrintValidTypes() {
    common->Printf( "valid types: " );
    for ( int i = 0; i < declManagerLocal.GetNumDeclTypes(); i++ ) {
        const idDeclType *declType = declManagerLocal.GetDeclType( i );
        if ( declType ) {
            common->Printf( "%s ", declType->typeName.c_str() );
        }
    }
    common->Printf( "\n" );
}

void idDeclManagerLocal::ResaveDecl_f( const idCmdArgs &args ) {
    if ( args.Argc() < 2 ) {
        common->Printf( "usage: resaveDecl <type> [name]\n" );
        DeclManager_PrintValidTypes();
        return;
    }
    
    const declType_t type = declManagerLocal.GetDeclTypeFromName( args.Argv( 1 ) );
    if ( type == DECL_MAX_TYPES ) {
        common->Printf( "unknown decl type '%s'\n", args.Argv( 1 ) );
        return;
    }
    
    if ( args.Argc() <= 2 ) {
        for ( int declIndex = 0; declIndex < declManagerLocal.GetNumDecls( type ); declIndex++ ) {
            const idDecl *decl = declManagerLocal.DeclByIndex( type, declIndex );
            common->Printf( "...resaving: %s\n", decl->GetName() );
            const_cast<idDecl *>( decl )->RebuildTextSource();
            const_cast<idDecl *>( decl )->ReplaceSourceFileText();
        }
        return;
    }
    
    const idDecl *decl = declManagerLocal.FindType( type, args.Argv( 2 ), true );
    if ( decl == NULL ) {
        common->Printf( "%s '%s' not found\n", declManagerLocal.GetDeclNameFromType( type ), args.Argv( 2 ) );
        return;
    }
    
    common->Printf( "...resaving: %s\n", decl->GetName() );
    const_cast<idDecl *>( decl )->RebuildTextSource();
    const_cast<idDecl *>( decl )->ReplaceSourceFileText();
}

/*
 ===================
 idDeclManagerLocal::WriteDeclFile_f
 ===================
 */
void idDeclManagerLocal::WriteDeclFile_f( const idCmdArgs &args ) {
    if ( args.Argc() > 2 ) {
        common->Printf( "usage: writeDeclFile [openq4|retail]\n" );
        return;
    }
    
    if ( args.Argc() == 2 ) {
        declSingleFileWriteMode_t writeMode;
        if ( !DeclManager_ParseSingleDeclWriteMode( args.Argv( 1 ), writeMode ) ) {
            common->Printf( "Unknown packed decl write mode '%s'. Use 'openq4' or 'retail'.\n", args.Argv( 1 ) );
            return;
        }
        
        declManagerLocal.WriteDeclFileWithMode( writeMode );
        return;
    }
    
    declManagerLocal.WriteDeclFile();
}

/*
 ===================
 idDeclManagerLocal::FlushDecls_f
 ===================
 */
void idDeclManagerLocal::FlushDecls_f( const idCmdArgs &args ) {
    (void)args;
    declManagerLocal.FlushDecls();
}

/*
 ===================
 idDeclManagerLocal::CheckDecls_f
 ===================
 */
void idDeclManagerLocal::CheckDecls_f( const idCmdArgs &args ) {
    (void)args;
    declManagerLocal.CheckDecls();
}

/*
 ===================
 idDeclManagerLocal::TouchDecl_f
 ===================
 */
void idDeclManagerLocal::TouchDecl_f( const idCmdArgs &args ) {
    if ( args.Argc() != 3 ) {
        common->Printf( "usage: touch <type> <name>\n" );
        DeclManager_PrintValidTypes();
        return;
    }
    
    const declType_t type = declManagerLocal.GetDeclTypeFromName( args.Argv( 1 ) );
    if ( type == DECL_MAX_TYPES ) {
        common->Printf( "unknown decl type '%s'\n", args.Argv( 1 ) );
        return;
    }
    
    const idDecl *decl = declManagerLocal.FindType( type, args.Argv( 2 ), true );
    if ( !decl ) {
        common->Printf( "%s '%s' not found\n", declManagerLocal.GetDeclNameFromType( type ), args.Argv( 2 ) );
    }
}
#endif

-(idDeclLocal *)findTypeWithoutParsing:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault indexToStoreAt:(int)indexToStoreAt {
    int typeIndex = (int)type;
    
    if (typeIndex < 0 || typeIndex >= [self numDeclTypes] || declTypes[typeIndex] == nil) {
        //common->FatalError( "idDeclManager::FindTypeWithoutParsing: bad type: %i", typeIndex );
        return nil; // TODO: throw
    }
    
    
    NSMutableString *lookupName = [idDeclManager makeCanonicalName:name];
    
    // see if it already exists
    NSNumber *declLocalIndex = hashTables[typeIndex][lookupName];
    if (declLocalIndex) {
        // only print these when decl_show is set to 2, because it can be a lot of clutter
        if (_workspace.decl_show > 1) {
            [self mediaPrint:@"referencing %@ %@\n", [declTypes[type] typeName], name];
        }
        return linearLists[typeIndex][[declLocalIndex integerValue]];
    }
    
    if (!makeDefault) {
        return nil;
    }
    
    idDeclLocal *decl = [[idDeclLocal alloc] init];
    decl->declManager = self;
    decl->selfDecl = nil;
    decl->name = [lookupName mutableCopy];
    decl->type = type;
    decl->declState = DS_UNPARSED;
    decl->textSource = nil;
    decl->textLength = 0;
    decl->sourceFile = implicitDecls;
    decl->referencedThisLevel = NO;
    decl->everReferenced = NO;
    decl->parsedOutsideLevelLoad = !insideLevelLoad;
    
    if (indexToStoreAt >= 0) {
        while (linearLists[typeIndex].count < indexToStoreAt) {
            idDeclLocal *placeholder = [[idDeclLocal alloc] init];
            placeholder->declManager = self;
            placeholder->name = [@"" mutableCopy];
            placeholder->type = type;
            placeholder->sourceFile = implicitDecls;
            placeholder->parsedOutsideLevelLoad = !insideLevelLoad;
            placeholder->index = (int)linearLists[typeIndex].count;
            [linearLists[typeIndex] addObject:placeholder];
        }
        
        decl->index = indexToStoreAt;
        if (indexToStoreAt < linearLists[typeIndex].count) {
            idDeclLocal *oldDecl = linearLists[typeIndex][indexToStoreAt];
            if (oldDecl != nil && oldDecl->name.length > 0) {
                [hashTables[typeIndex] removeObjectForKey:oldDecl->name];
            }
            [self deleteLocalDecl:oldDecl];
            [linearLists[typeIndex] setObject:decl atIndexedSubscript:indexToStoreAt];
        } else {
            [linearLists[typeIndex] addObject:decl];
        }
        [hashTables[typeIndex] setObject:@(indexToStoreAt) forKey:lookupName];
        return decl;
    }
    
    // add it to the linear list and hash table
    decl->index = (int)linearLists[typeIndex].count;
    [linearLists[typeIndex] addObject:decl];
    [hashTables[typeIndex] setObject:@(decl->index) forKey:lookupName];
    
    return decl;
}

-(idDeclLocal *)findTypeWithoutParsing:(declType_t)type name:(NSString *)name makeDefault:(BOOL)makeDefault/*true*/ {
    return [self findTypeWithoutParsing:type name:name makeDefault:makeDefault indexToStoreAt:-1];
}

-(idDeclLocal *)findTypeWithoutParsing:(declType_t)type name:(NSString *)name indexToStoreAt:(int)indexToStoreAt; {
    return [self findTypeWithoutParsing:type name:name makeDefault:YES indexToStoreAt:indexToStoreAt];
}

-(idDeclLocal *)findTypeWithoutParsing:(declType_t)type name:(NSString *)name {
    return [self findTypeWithoutParsing:type name:name makeDefault:YES indexToStoreAt:-1];
}

-(idDeclType *)declType:(int)type { return declTypes[type]; }
-(const idDeclFile *)implicitDeclFile { return implicitDecls; }

@end

/*
 ====================================================================================
 
 idDeclFile
 
 ====================================================================================
 */

@implementation idDeclFile

-(instancetype)initWithFileName:(NSString *)filename defaultType:(declType_t)defaultType manager:(idDeclManager *)manager {
    self = [super init];
    if (self) {
        self->fileName = [filename mutableCopy];
        self->defaultType = defaultType;
        self->timestamp = 0;
        self->checksum = 0;
        self->fileSize = 0;
        self->numLines = 0;
        self->decls = nil;
        self->declManager = manager;
    }
    return self;
}

/*
// TODO: remove this?
-(instancetype)init {
    self = [super init];
    if (self) {
        self->fileName = [@"<implicit file>" mutableCopy];
        self->defaultType = DECL_MAX_TYPES;
        self->timestamp = 0;
        self->checksum = 0;
        self->fileSize = 0;
        self->numLines = 0;
        self->decls = nil;
    }
    return self;
}*/

-(int)reload:(BOOL)force error:(NSError **)error {
    // check for an unchanged timestamp
    if (!force && timestamp != 0) {
        unsigned int    testTimeStamp;
        int ret = [declManager.workspace.fileSystem readFile:fileName buffer:NULL timestamp:&testTimeStamp error:error];
        if (ret == -1) {
            return -1;
        }
        
        if (testTimeStamp == timestamp) {
            return 0; // FIXME: what to return?
        }
    }
    
    // parse the text
    return [self loadAndParse:YES error:error];
}

-(int)loadAndParse:(BOOL)unique error:(NSError **)error {
    int            i, numTypes;
    idLexer *      src;
    idToken        token;
    int            startMarker;
    char *         buffer;
    int            length, size;
    int            sourceLine;
    NSMutableString *name;
    NSMutableString *strippedName;
    idDeclLocal *newDecl;
    bool        referencedThisLevel;
    
    // load the text
    NSLog(@"...loading '%@'\n", fileName);
    length = [declManager.workspace.fileSystem readFile:fileName buffer:(void **)&buffer timestamp:&timestamp error:error];
    if (length == -1) {
        //common->FatalError( "couldn't load %s", fileName.c_str() );
        return 0;
    }
    const char *finalPreprocessedBuffer = (const char *)buffer;
    
    idToken_Init(&token);

    strippedName = [[fileName stringByDeletingPathExtension] mutableCopy];

    src = [[idLexer alloc] initWithFileSystem:declManager.workspace.fileSystem];
    
    if (![src loadMemory:finalPreprocessedBuffer length:length name:fileName startLine:1 error:error]) {
        //common->Error( "Couldn't parse %s", fileName.c_str() );
        return 0;
    }
    
    // mark all the defs that were from the last reload of this file
    for (idDeclLocal *decl = decls; decl; decl = decl->nextInFile) {
        decl->redefinedInReload = NO;
    }
    
    [src setFlags:DECL_LEXER_FLAGS];

    checksum = MD5_BlockChecksum(finalPreprocessedBuffer, length);
    fileSize = length;
    
    name = [[NSMutableString alloc] init];

    // scan through, identifying each individual declaration
    while (1) {
        
        startMarker = [src fileOffset];
        sourceLine = [src lineNum];
        
        // parse the decl type name
        if (![src readToken:&token error:error]) {
            break;
        }
        
        BOOL guide = NO;
        if (strcasecmp(token.text, "guide") == 0) {
            guide = YES;
            if (![src readToken:&token error:error]) {
                [src warning:@"Type without definition at end of file"];
                break;
            }
        }
        
        declType_t identifiedType = DECL_MAX_TYPES;
        
        // get the decl type from the type name
        numTypes = [declManager numDeclTypes];
        for (i = 0; i < numTypes; i++) {
            idDeclType *typeInfo = [declManager declType:i];
            if (typeInfo && strcasecmp([typeInfo.typeName UTF8String], token.text) == 0) {
                identifiedType = (declType_t) typeInfo.type;
                break;
            }
        }
        
        if (i >= numTypes) {
            
            if (strcasecmp(token.text, "{") == 0) {
                // if we ever see an open brace, we somehow missed the [type] <name> prefix
                [src warning:@"Missing decl name"];
                [src skipBracedSection:NO error:error];
                continue;
                
            } else {
                
                if (defaultType == DECL_MAX_TYPES) {
                    [src warning:@"No type"];
                    continue;
                }
                [src unreadToken:&token error:error];
                // use the default type
                identifiedType = defaultType;
            }
        }
        
        // now parse the name
        if (![src readToken:&token error:error]) {
            [src warning:@"Type without definition at end of file"];
            break;
        }
        
        if (!strcasecmp(token.text, "{")) {
            // if we ever see an open brace, we somehow missed the [type] <name> prefix
            [src warning:@"Missing decl name"];
            [src skipBracedSection:NO error:error];
            continue;
        }
        
        // FIXME: export decls are only used by the model exporter, they are skipped here for now
        if (identifiedType == DECL_MODELEXPORT) {
            [src skipBracedSection:YES error:error];
            continue;
        }
        
        [name setString:@""];
        [name appendFormat:@"%s", token.text];

        const BOOL uniqueNameMismatch = unique && [strippedName compare:name] != NSOrderedSame;
        if (uniqueNameMismatch && defaultType != DECL_EFFECT) {
            [src warning:@"%@ must be in a file of the same name", name];
        }
        
        NSMutableString *declDefinition = [[NSMutableString alloc] init];
        if (guide) {
            [declManager evaluateGuide:name source:src definition:declDefinition error:error];
        } else {
            [src parseBracedSectionExact:declDefinition tabs:-1 error:error];
        }
        [declManager evaluateInlineGuide:name definition:declDefinition error:error];
        size = [src fileOffset] - startMarker;
        
        // look it up, possibly getting a newly created default decl
        referencedThisLevel = NO;
        newDecl = [declManager findTypeWithoutParsing:identifiedType name:name makeDefault:NO];
        if (newDecl) {
            // update the existing copy
            if (newDecl->sourceFile == self && !newDecl->redefinedInReload) {
                referencedThisLevel = newDecl->referencedThisLevel;
            } else {
                /*
                if (!DeclManager_IsopenQ4OverrideDeclFile(newDecl->sourceFile) &&
                    !DeclManager_IsStockMaterialRedeclaration(identifiedType, name, newDecl->sourceFile, this)) {
                    src.Warning( "%s '%s' previously defined at %s:%i", declManagerLocal.GetDeclNameFromType( identifiedType ),
                                name.c_str(), newDecl->sourceFile->fileName.c_str(), newDecl->sourceLine );
                }*/
                continue;
            }
        } else {
            // allow it to be created as a default, then add it to the per-file list
            newDecl = [declManager findTypeWithoutParsing:identifiedType name:name makeDefault:YES];
            newDecl->nextInFile = self->decls;
            self->decls = newDecl;
        }
        
        newDecl->redefinedInReload = YES;
        
        if (newDecl->textSource) {
            newDecl->textSource = nil;
        }

        // FIXME: remove the overhead of converting to NSMutableData
        NSMutableData *tempData = [[NSMutableData alloc] init];
        [tempData appendUTF8StringAndNullTerminate:declDefinition.UTF8String];
        [newDecl setTextLocal:tempData];
        newDecl->sourceFile = self;
        newDecl->sourceTextOffset = startMarker;
        newDecl->sourceTextLength = size;
        newDecl->sourceLine = sourceLine;
        newDecl->declState = DS_UNPARSED;
        
        // if it is currently in use, or the program-image writer needs every material parsed, reparse it immediately
        if (referencedThisLevel || DeclManager_WriteProgramImagesEnabled()) {
            [newDecl parseLocal:NO error:error];
        }
        
        if (uniqueNameMismatch && identifiedType == DECL_EFFECT) {
            idDeclLocal *aliasDecl = [declManager findTypeWithoutParsing:identifiedType name:strippedName makeDefault:NO];
            referencedThisLevel = NO;
            if (aliasDecl) {
                if (aliasDecl->sourceFile == self && !aliasDecl->redefinedInReload) {
                    referencedThisLevel = aliasDecl->referencedThisLevel;
                /*} else if (!DeclManager_IsopenQ4OverrideDeclFile(aliasDecl->sourceFile)) {
                    aliasDecl = NULL;
                */
                }
            } else {
                aliasDecl = [declManager findTypeWithoutParsing:identifiedType name:strippedName makeDefault:YES];
                aliasDecl->nextInFile = self->decls;
                self->decls = aliasDecl;
            }
            
            if (aliasDecl != NULL) {
                aliasDecl->redefinedInReload = YES;
                
                if (aliasDecl->textSource) {
                    //free(aliasDecl->textSource);
                    aliasDecl->textSource = NULL;
                }

                // FIXME: remove the overhead of converting to NSMutableData
                NSMutableData *tempData = [[NSMutableData alloc] init];
                [tempData appendUTF8StringAndNullTerminate:declDefinition.UTF8String];
                [aliasDecl setTextLocal:tempData];
                aliasDecl->sourceFile = self;
                aliasDecl->sourceTextOffset = startMarker;
                aliasDecl->sourceTextLength = size;
                aliasDecl->sourceLine = sourceLine;
                aliasDecl->declState = DS_UNPARSED;
                
                if (referencedThisLevel || DeclManager_WriteProgramImagesEnabled()) {
                    [aliasDecl parseLocal:NO error:error];
                }
            }
        }
        
        if (unique) {
            break;
        }
    }
    
    numLines = [src lineNum];
    
    // any defs that weren't redefinedInReload should now be defaulted
    for (idDeclLocal *decl = decls ; decl ; decl = decl->nextInFile) {
        if (decl->redefinedInReload == NO) {
            [decl makeDefault:error];
            decl->sourceTextOffset = decl->sourceFile->fileSize;
            decl->sourceTextLength = 0;
            decl->sourceLine = decl->sourceFile->numLines;
        }
    }
    
    return checksum;
}

-(int)loadAndParseFrom:(idFile *)file error:(NSError **)error {
    NSMutableString *declCountString = [[NSMutableString alloc] init];
    if (!readPackedDeclLine(file, declCountString, error)) {
        //common->Warning( "Missing decl count while loading packed decl file '%s'", fileName.c_str() );
        return 0;
    }
    
    const int declCount = [declCountString integerValue];
    for (idDeclLocal *decl = decls; decl; decl = decl->nextInFile) {
        decl->redefinedInReload = NO;
    }
    
    NSMutableString *indexString = [[NSMutableString alloc] init];
    NSMutableString *sizeString = [[NSMutableString alloc] init];

    for (int packedDeclIndex = 0; packedDeclIndex < declCount; packedDeclIndex++) {
        [indexString setString:@""];
        [sizeString setString:@""];
        
        if (!readPackedDeclLine(file, indexString, error) || !readPackedDeclLine(file, sizeString, error)) {
            NSLog(@"Truncated packed decl metadata in '%@'", fileName);
            break;
        }
        
        const int indexToStoreAt = [indexString integerValue];
        const int packedTextLength = [sizeString integerValue];
        if (packedTextLength <= 0) {
            NSLog(@"Invalid packed decl length %d in '%@'", packedTextLength, fileName);
            continue;
        }
        
        NSMutableData *buffer = [[NSMutableData alloc] initWithLength:packedTextLength + 1];
        
        const int readBytes = [file read:buffer.mutableBytes length:packedTextLength error:error];
        if (readBytes <= 0) {
            NSLog(@"Could not read packed decl text in '%@'", fileName);
            break;
        }
        [buffer setLength:packedTextLength];
        ((unsigned char *)buffer.mutableBytes)[readBytes] = '\0';
        
        checksum = MD5_BlockChecksum(buffer.bytes, readBytes);
        
        fileSize = readBytes;
        
        idLexer *src = [[idLexer alloc] initWithFlags:DECL_LEXER_FLAGS fileSystem:declManager.workspace.fileSystem];
        idToken token;
        if (![src loadMemory:buffer.bytes length:packedTextLength name:fileName startLine:1 error:error]) {
            NSLog(@"Couldn't parse packed decl text in '%@'", fileName);
            continue;
        }
        
        const int startMarker = [src fileOffset];
        const int sourceLine = [src lineNum];
        
        if (![src readToken:&token error:error]) {
            break;
        }
        
        BOOL guide = NO;
        if (strcasecmp(token.text, "guide") == 0) {
            guide = YES;
            if (![src readToken:&token error:error]) {
                [src warning:@"Type without definition at end of packed decl"];
                break;
            }
        }
        
        declType_t identifiedType = DECL_MAX_TYPES;
        const int numTypes = [declManager numDeclTypes];
        for (int i = 0; i < numTypes; i++) {
            idDeclType *typeInfo = [declManager declType:i];
            if (typeInfo && [[typeInfo typeName] caseInsensitiveCompare:[NSString stringWithCString:token.text]] == NSOrderedSame) {
                identifiedType = (declType_t)[typeInfo type];
                break;
            }
        }
        
        if (identifiedType == DECL_MAX_TYPES) {
            if (strcmp(token.text, "{") == 0) {
                [src warning:@"Missing decl name"];
                [src skipBracedSection:NO error:error];
                continue;
            }
            if (defaultType == DECL_MAX_TYPES) {
                [src warning:@"No type"];
                continue;
            }
            [src unreadToken:&token error:error];
            identifiedType = defaultType;
        }
        
        if (![src readToken:&token error:error]) {
            [src warning:@"Type without definition at end of packed decl"];
            break;
        }
        
        if (strcmp(token.text, "{") == 0) {
            [src warning:@"Missing decl name"];
            [src skipBracedSection:NO error:error];
            continue;
        }
        
        if (identifiedType == DECL_MODELEXPORT) {
            [src skipBracedSection:YES error:error];
            continue;
        }
        
        NSMutableString *name = [NSMutableString stringWithCString:token.text encoding:NSUTF8StringEncoding];
        NSMutableString *declDefinition = [[NSMutableString alloc] init];
        
        if (guide) {
            [declManager evaluateGuide:name source:src definition:declDefinition error:error];
        } else {
            [src parseBracedSectionExact:declDefinition tabs:-1 error:error];
        }
        [declManager evaluateInlineGuide:name definition:declDefinition error:error];
        int sourceTextLength = [src fileOffset] - startMarker;
        
        idDeclLocal *decl = [declManager findTypeWithoutParsing:identifiedType name:name makeDefault:NO];
        if (decl) {
            if (decl->sourceFile != self || decl->redefinedInReload) {
                /*
                if ( !DeclManager_IsopenQ4OverrideDeclFile( decl->sourceFile ) &&
                    !DeclManager_IsStockMaterialRedeclaration( identifiedType, name, decl->sourceFile, this ) ) {
                    src.Warning( "%s '%s' previously defined at %s:%i",
                                declManagerLocal.GetDeclNameFromType( identifiedType ),
                                name.c_str(),
                                decl->sourceFile ? decl->sourceFile->fileName.c_str() : "*unknown*",
                                decl->sourceLine );
                }*/
                continue;
            }
        } else {
            decl = [declManager findTypeWithoutParsing:identifiedType name:name makeDefault:YES indexToStoreAt:indexToStoreAt];
            decl->nextInFile = self->decls;
            self->decls = decl;
        }
        
        decl->declState = DS_UNPARSED;
        decl->redefinedInReload = YES;
        if (decl->textSource) {
            if (decl->needsPrecache) {
                continue;
            }
            //free(decl->textSource);
            decl->textSource = nil;
        }
        
        if (!decl->needsPrecache) {
            const char *rawDeclDefinition = declDefinition.UTF8String;
            int len = strlen(rawDeclDefinition);

            [decl setTextLocal:[[NSMutableData alloc] initWithBytes:rawDeclDefinition length:len + 1]];
            decl->sourceFile = self;
            decl->sourceTextOffset = startMarker;
            decl->sourceTextLength = sourceTextLength;
            decl->sourceLine = sourceLine;
        }
    }
    
    for (idDeclLocal *decl = decls; decl; decl = decl->nextInFile) {
        if (decl->redefinedInReload == NO) {
            [decl makeDefault:error];
            decl->sourceTextOffset = decl->sourceFile->fileSize;
            decl->sourceTextLength = 0;
            decl->sourceLine = decl->sourceFile->numLines;
        }
    }
    
    return checksum;
}

@end

#if 0


/*
 ====================================================================================
 
 idDeclManagerLocal
 
 ====================================================================================
 */

const char *listDeclStrings[] = { "current", "all", "ever", NULL };

// material decls are renderer-owned types; allocate through the renderer
// interface so framework code carries no renderer symbol dependency
static idDecl *openQ4_MaterialDeclAllocator( void ) {
    return renderSystem->AllocMaterialDecl();
}

// jmarshall: Quake 4 Guide Support
/*
 =========================
 idDeclManagerLocal::GetNewGuide
 =========================
 */
rvDeclGuide *idDeclManagerLocal::GetNewGuide( idLexer *src, idStr &file ) {
    idToken guideName;
    if ( !src->ReadToken( &guideName ) ) {
        common->Printf( "Guide file '%s' has unknown token '%s'\n", file.c_str(), guideName.c_str() );
        return NULL;
    }

    if ( DeclManager_FindGuide( guideName.c_str() ) != NULL ) {
        common->Printf( "Guide file '%s' contains duplicate guide '%s'\n", file.c_str(), guideName.c_str() );
        src->SkipBracedSection( true );
        return NULL;
    }
    
    rvDeclGuide *guide = new rvDeclGuide( guideName );
    guide->Parse( src );
    return guide;
}

/*
 =========================
 rvDeclGuide::rvDeclGuide
 =========================
 */
rvDeclGuide::rvDeclGuide( idStr &name ) {
    mName = name;
    mNumParms = 0;
}

/*
 =========================
 rvDeclGuide::~rvDeclGuide
 =========================
 */
rvDeclGuide::~rvDeclGuide( void ) {
}

/*
 =========================
 rvDeclGuide::SetParm
 =========================
 */
void rvDeclGuide::SetParm( int index, const char *value ) {
    assert( index >= 0 && index < MAX_GUIDE_PARMS );
    if ( index < 0 || index >= MAX_GUIDE_PARMS ) {
        return;
    }
    mParms[index] = value;
    if ( index >= mNumParms ) {
        mNumParms = index + 1;
    }
}

/*
 =========================
 rvDeclGuide::Parse
 =========================
 */
void rvDeclGuide::Parse( idLexer *src ) {
    idToken token;
    int commaCount = 0;
    
    src->ExpectTokenString( "(" );
    mNumParms = 0;
    
    while ( src->ReadToken( &token ) && token.Cmp( ")" ) != 0 ) {
        if ( token.Cmp( "," ) != 0 ) {
            if ( mNumParms < MAX_GUIDE_PARMS ) {
                mParms[mNumParms] = token;
            }
            mNumParms++;
        } else {
            commaCount++;
        }
    }
    
    if ( commaCount != mNumParms - 1 ) {
        src->Warning( "Guide name '%s' only contains %d commas for %d args, expecting %d! Typo?\n",
                     mName.c_str(), commaCount, mNumParms, mNumParms - 1 );
    }
    
    src->ParseBracedSectionExact( mDefinition, -1 );
}

/*
 =========================
 rvDeclGuide::RemoveOuterBracing
 =========================
 */
void rvDeclGuide::RemoveOuterBracing( void ) {
    const int closeBrace = mDefinition.Last( '}' );
    if ( closeBrace > 0 ) {
        mDefinition = mDefinition.Left( closeBrace - 1 );
    }
    
    const int openBrace = mDefinition.Find( '{' );
    if ( openBrace >= 0 ) {
        mDefinition = mDefinition.Mid( openBrace + 1, mDefinition.Length() - openBrace - 1 );
    }
}

/*
 =========================
 rvDeclGuide::Evaluate
 =========================
 */
bool rvDeclGuide::Evaluate( idLexer *src, idStr &definition ) {
    idToken token;
    idStr arguments[MAX_GUIDE_PARMS];
    int numArgs = 0;
    
    definition.Empty();
    src->ExpectTokenString( "(" );
    while ( numArgs < MAX_GUIDE_PARMS && src->ReadToken( &token ) ) {
        if ( token.Cmp( ")" ) == 0 ) {
            break;
        }
        if ( token.Cmp( "," ) == 0 ) {
            continue;
        }
        arguments[numArgs++] = token;
    }
    
    if ( numArgs != mNumParms ) {
        return false;
    }
    
    definition = mDefinition;
    
    for ( int i = 0; i < mNumParms && i < MAX_GUIDE_PARMS; i++ ) {
        const int parmLength = mParms[i].Length();
        if ( parmLength <= 0 ) {
            continue;
        }
        
        int searchOffset = 0;
        while ( searchOffset <= definition.Length() ) {
            const char *match = strstr( definition.c_str() + searchOffset, mParms[i].c_str() );
            if ( match == NULL ) {
                break;
            }
            
            const int matchOffset = (int)( match - definition.c_str() );
            idStr prefix = definition.Mid( 0, matchOffset );
            idStr suffix = definition.Mid( matchOffset + parmLength, definition.Length() - matchOffset - parmLength );
            definition = prefix + arguments[i] + suffix;
            searchOffset = matchOffset + arguments[i].Length();
        }
    }
    
    return true;
}

// jmarshall end
#endif

/*
 ====================================================================================
 
 idDeclLocal
 
 ====================================================================================
 */

@implementation idDeclLocal

-(instancetype)init {
    self = [super init];
    if (self) {
        selfDecl = nil;
        insideLevelLoad = NO;
        name = [@"unnamed" mutableCopy];
        textSource = nil;
        textLength = 0;
        sourceFile = nil;
        sourceTextOffset = 0;
        sourceTextLength = 0;
        sourceLine = 0;
        checksum = 0;
        type = DECL_ENTITYDEF;
        index = 0;
        declState = DS_UNPARSED;
        parsedOutsideLevelLoad = NO;
        referencedThisLevel = NO;
        everReferenced = NO;
        redefinedInReload = NO;
        needsPrecache = NO;
        nextInFile = nil;
    }
    return self;
}

-(NSString *)name {
    return self->name;
}

-(declType_t)type {
    return self->type;
}

-(declState_t)state {
    return self->declState;
}

-(BOOL)isImplicit {
    return (sourceFile == [declManager implicitDeclFile]);
}

-(BOOL)isValid {
    return (declState != DS_UNPARSED);
}

-(void)invalidate {
    declState = DS_UNPARSED;
}

-(void)ensureNotPurged {
    if (declState == DS_UNPARSED) {
        [self parseLocal:NO error:nil];
    }
}

-(int)index {
    return self->index;
}

-(int)lineNum {
    return self->sourceLine;
}

-(NSString *)fileName {
    if (self->sourceFile == nil) {
        return @"";
    }
    return sourceFile->fileName;
}

-(size_t)size {
    return 0;
    //return sizeof(idDecl) + [name allocated];
}

-(void)text:(NSMutableData *)buffer {
    buffer.length = textLength + 1;
#ifdef USE_COMPRESSED_DECLS
    HuffmanDecompressText(buffer, textSource);
#else
    memcpy(buffer.mutableBytes, textSource.bytes, textLength);
    ((char *)buffer.mutableBytes)[textLength] = '\0';
#endif
}

-(int)textLength {
    return self->textLength;
}

-(int)compressedLength {
    return self->textSource ? self->textSource.length : 0;
}

-(void)setText:(NSMutableData *)text {
    [self setTextLocal:text];
}

- (void)setTextLocal:(NSMutableData *)text {
    // 1. Release the old memory immediately
    self->textSource = nil;

    if (!text || text.length == 0) {
        self->textLength = 0;
        self->checksum = 0;
        return;
    }

    // 2. Safely extract the raw C-string and its byte length
    const char *rawText = (char*)text.mutableBytes;
    int length = (int)text.length - 1; // without the 0 terminator

    // 3. Calculate Checksum
    self->checksum = MD5_BlockChecksum(rawText, length);
    self->textLength = length;

#ifdef USE_COMPRESSED_DECLS
    int maxBytesPerCode = (maxHuffmanBits + 7) >> 3;
    int maxCompressedSize = length * maxBytesPerCode;

    NSMutableData *tempCompressed = [NSMutableData dataWithLength:maxCompressedSize];

    int compressedLength = HuffmanCompressText(text, tempCompressed);

    self->textSource = tempCompressed;
#else
    // Store the raw string bytes, including the +1 for the null terminator
    self->textSource = [NSMutableData dataWithBytes:rawText length:length+1];
#endif
}

-(BOOL)replaceSourceFileText:(NSError **)error {
    int oldFileLength, newFileLength;
    NSMutableData *buffer;
    idFile *file;
    
    NSLog(@"Writing \'%@\' to \'%@\'...\n", [self name], [self fileName]);
    
    if (sourceFile == [declManager implicitDeclFile]) {
        NSLog(@"Can't save implicit declaration %@.", [self name]);
        return NO;
    }
    
#define Max(a,b) ((a) > (b) ? (a) : (b))
    
    // get length and allocate buffer to hold the file
    oldFileLength = sourceFile->fileSize;
    newFileLength = oldFileLength - self->sourceTextLength + self->textLength;
    buffer = [[NSMutableData alloc] initWithCapacity:Max(newFileLength, oldFileLength)];
    
#undef Max
    
    // read original file
    if (sourceFile->fileSize) {
        
        file = [declManager.workspace.fileSystem openFileRead:[self fileName] allowCopyFiles:YES gamedir:nil error:error];
        if (!file) {
            NSLog(@"Couldn't open %@ for reading.", [self fileName]);
            return NO;
        }
        
        if ([file length] != sourceFile->fileSize || [file timestamp] != sourceFile->timestamp) {
            NSLog(@"The file %@ has been modified outside of the engine.", [self fileName]);
            return [declManager.workspace.fileSystem closeFile:file error:error];
        }
        
        if (![file read:buffer.mutableBytes length:oldFileLength error:error]) {
            return [declManager.workspace.fileSystem closeFile:file error:error];
        }

        if (![declManager.workspace.fileSystem closeFile:file error:error]) {
            return NO;
        }

        if (MD5_BlockChecksum(buffer.bytes, oldFileLength) != sourceFile->checksum) {
            NSLog(@"The file %@ has been modified outside of the engine.", [self fileName]);
            return NO;
        }
    }
    
    // insert new text
    NSMutableData *declText = [[NSMutableData alloc] init];
    [self text:declText];
    
    memmove(buffer.mutableBytes + self->sourceTextOffset + self->textLength, buffer.mutableBytes + self->sourceTextOffset + self->sourceTextLength, oldFileLength - self->sourceTextOffset - self->sourceTextLength);
    memcpy(buffer.mutableBytes + self->sourceTextOffset, declText.mutableBytes, self->textLength);

    // write out new file
    file = [declManager.workspace.fileSystem openFileWrite:[self fileName] basePath:@"fs_savepath" error:error];
    if (!file) {
        //common->Warning( "Couldn't open %s for writing.", GetFileName() );
        return NO;
    }
    [file write:buffer.bytes length:newFileLength error:error];
    [declManager.workspace.fileSystem closeFile:file error:error];

    // set new file size, checksum and timestamp
    sourceFile->fileSize = newFileLength;
    sourceFile->checksum = MD5_BlockChecksum(buffer.bytes, newFileLength);
    [declManager.workspace.fileSystem readFile:[self fileName] buffer:NULL timestamp:&sourceFile->timestamp error:error];
    
    // free buffer
    buffer = nil;
    
    // move all decls in the same file
    for (idDeclLocal *decl = sourceFile->decls; decl; decl = decl->nextInFile) {
        if (decl->sourceTextOffset > sourceTextOffset) {
            decl->sourceTextOffset += textLength - sourceTextLength;
        }
    }
    
    // set new size of text in source file
    sourceTextLength = textLength;
    
    return YES;
}

-(BOOL)sourceFileChanged {
    int newLength;
    unsigned int newTimestamp;
    NSError *error = nil;

    if (declManager.workspace.com_SingleDeclFile) {
        return NO;
    }
    
    if (sourceFile->fileSize <= 0) {
        return NO;
    }
    
    newLength = [declManager.workspace.fileSystem readFile:[self fileName] buffer:NULL timestamp:&newTimestamp error:&error];
    if (error) {
        return NO; // TODO: log this?
    }
    
    if (newLength != sourceFile->fileSize || newTimestamp != sourceFile->timestamp) {
        return YES;
    }
    
    return NO;
}

-(BOOL)makeDefault:(NSError **)error {
    static int recursionLevel;
    NSMutableData *defaultText;
    
    [declManager mediaPrint:@"DEFAULTED\n"];
    declState = DS_DEFAULTED;
    
    [self allocateSelf];
    
    NSString *defaultDef = [selfDecl defaultDefinition];

    defaultText = [[NSMutableData alloc] init];
    [defaultText appendUTF8StringAndNullTerminate:defaultDef.UTF8String];

    // a parse error inside a DefaultDefinition() string could
    // cause an infinite loop, but normal default definitions could
    // still reference other default definitions, so we can't
    // just dump out on the first recursion
    if (++recursionLevel > 100) {
        //common->FatalError( "idDecl::MakeDefault: bad DefaultDefinition(): %s", defaultText );
        return NO;
    }
    
    // always free data before parsing
    [selfDecl freeData];
    
    // parse
    BOOL ret = [selfDecl parse:defaultText noCaching:NO error:error];

    // we could still eventually hit the recursion if we have enough Error() calls inside Parse...
    --recursionLevel;
    
    return ret;
}

-(BOOL)setDefaultText {
    return NO;
}

-(NSString *)defaultDefinition {
    return @"{ }";
}

-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)cache error:(NSError **)error {
    idLexer *src = [[idLexer alloc] initWithFlags:DECL_LEXER_FLAGS fileSystem:declManager.workspace.fileSystem];
    
    if (![src loadMemory:text.bytes length:text.length-1 name:[self fileName] startLine:[self lineNum] error:error]) {
        return NO;
    }
    if (![src skipUntilString:@"{" error:error]) {
        return NO;
    }
    if (![src skipBracedSection:NO error:error]) {
        return NO;
    }
    
    return YES;
}

-(void)freeData {
}

-(void)list {
    NSLog(@"%@", [self name]);
}

-(void)print {
}

-(void)reload {
    [self->sourceFile reload:NO error:nil];
}

-(void)allocateSelf {
    if (self->selfDecl == nil) {
        self->selfDecl = [[declManager declType:(int)self->type] allocator]();
        self->selfDecl.declManager = self->declManager;
        [self->selfDecl setBase:self];
    }
}

-(BOOL)parseLocal:(BOOL)noCaching error:(NSError **)error {
    BOOL generatedDefaultText = NO;
    
    [self allocateSelf];
    
    // always free data before parsing
    [selfDecl freeData];
    
    [declManager mediaPrint:@"parsing %@ %@", [declManager declTypeName:type], name];
    
    // if no text source try to generate default text
    if (self->textSource == nil) {
        generatedDefaultText = [selfDecl setDefaultText];
    }
    
    // indent for DEFAULTED or media file references
    [declManager incrIndent]; //    declManagerLocal.indent++;
    
    // no text immediately causes a MakeDefault()
    if (self->textSource == nil) {
        BOOL ret = [self makeDefault:error];
        [declManager decrIndent]; //   declManagerLocal.indent--;
        return ret;
    }
    
    self->declState = DS_PARSED;
    
    // parse
    NSMutableData *declText = [[NSMutableData alloc] initWithLength:[self textLength] + 1];
    [self text:declText];
    
    NSMutableData *parseText = declText;
    
    if (strncasecmp(parseText.bytes, "{ STUB:", 7) == 0) {
        idLexer *stubLexer = [[idLexer alloc] initWithFlags:DECL_LEXER_FLAGS fileSystem:declManager.workspace.fileSystem];
        if (![stubLexer loadMemory:parseText.bytes length:parseText.length-1 name:[self fileName] startLine:[self lineNum] error:error]) {
            return NO;
        }

        if ([stubLexer expectTokenString:@"{" error:error] && [stubLexer expectTokenString:@"STUB:" error:error]) {
            int stubOffset, stubLength;
            [stubLexer parseInt:&stubOffset error:error];
            [stubLexer parseInt:&stubLength error:error];

            [stubLexer expectTokenString:@"}" error:error];
            
            self->needsPrecache = YES;
            NSLog(@"You should precache: %@", [self name]);
            
            idFile *stubSource = [declManager.workspace.fileSystem openFileRead:sourceFile->fileName allowCopyFiles:YES gamedir:nil error:error];
            if (stubSource != nil) {
                NSMutableData *sourceText = [[NSMutableData alloc] initWithLength:stubLength+1];
                [stubSource seek:stubOffset origin:FS_SEEK_SET];
                const int readBytes = [stubSource read:sourceText.mutableBytes length:stubLength error:error];
                [declManager.workspace.fileSystem closeFile:stubSource error:error];
                
                if (readBytes > 0) {
                    [sourceText setLength:readBytes + 1];
                    ((unsigned char *)sourceText.mutableBytes)[readBytes] = '\0';
                    
                    NSMutableString *definition = [[NSMutableString alloc] init];
                    [definition appendFormat:@"%s", (char *)sourceText.bytes];
                    
                    idLexer *sourceLexer = [[idLexer alloc] initWithFlags:DECL_LEXER_FLAGS fileSystem:declManager.workspace.fileSystem];
                    idToken token;
                    idToken_Init(&token);
                    if (![sourceLexer loadMemory:sourceText.bytes
                                          length:readBytes
                                            name:sourceFile->fileName
                                       startLine:sourceLine
                                           error:error]) {
                        return NO;
                    }
                    if ([sourceLexer readToken:&token error:error] && strcasecmp(token.text, "guide") == 0) {
                        idToken guideDeclName;
                        idToken_Init(&guideDeclName);
                        if ([sourceLexer readToken:&guideDeclName error:error]) {
                            NSMutableString *guideName = [NSMutableString stringWithUTF8String:guideDeclName.text];
                            [declManager evaluateGuide:guideName source:sourceLexer definition:definition error:error];
                            [declManager evaluateInlineGuide:guideName definition:definition error:error];
                        }
                    } else {
                        [declManager evaluateInlineGuide:name definition:definition error:error];
                    }
                    
                    [self setTextLocal:sourceText];
                    parseText = sourceText;
                }
            } else {
                NSLog(@"Couldn't open %@ for reading packed decl stub.", sourceFile->fileName);
            }
        }
    }

#if 0
    if (/*common->IsInitialized() &&*/ ![self->declManager insideLoad] && !openQ4_IsAnyToolActive()) {
        NSLog(@"Loading non pre-cached %@ decl %@", [self->declManager declNameFromType:type], name);
    }
#endif
    
    BOOL parsed = [selfDecl parse:parseText noCaching:noCaching error:error];

    // free generated text
    if (generatedDefaultText || (declManager.workspace.com_SingleDeclFile && !needsPrecache)) {
        textSource = nil; //free(textSource);
        textLength = 0;
    }

    [declManager decrIndent]; // declManagerLocal.indent--;
    
    return parsed;
}

-(void)purge {
    // never purge things that were referenced outside level load,
    // like the console and menu graphics
    if (self->parsedOutsideLevelLoad) {
        return;
    }
    
    self->referencedThisLevel = NO;
    [self makeDefault:nil];

    // the next Find() for this will re-parse the real data
    self->declState = DS_UNPARSED;
}

-(BOOL)everReferenced {
    return self->everReferenced;
}

-(void)setReferencedThisLevel {
    referencedThisLevel = YES;
    everReferenced = YES;
}

-(BOOL)validate:(NSMutableData *)psText reportTo:(NSMutableString *)strReportTo {
    idDecl *decl = [declManager allocateDecl:self->type];
    const BOOL valid = DeclManager_ValidateParsedDecl(decl, type, decl != NULL && [decl parse:psText noCaching:NO error:nil]);
    DeclManager_FreeAllocatedDecl(decl);
    return valid;
}

@end
