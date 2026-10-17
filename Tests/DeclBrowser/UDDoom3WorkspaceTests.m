#import "UDDeclBrowserTestCase.h"

#import "UDDeclManagedObjects.h"
#import "UDMaterialParser.h"
#import "UDParticlePreview.h"
#import "UDDeclTextChecker.h"
#import "UDMD5Mesh.h"
#import "idFileSystem.h"
#import "UDEditorTabManager.h"
#import "UDPDAEditorViewController.h"
#import "UDEntityDefEditorViewController.h"
#import "UDTextEditorViewController.h"
#import "UDMaterialEditorViewController.h"
#import "UDWorkspace.h"
#import "UDWorkspaceDocument.h"
#import "UDBaseDocument.h"
#import "idDeclManager.h"
#import "idUserInterface.h"
#import "idGuiModel.h"
#import "UDGuiPlayer.h"
#import "UDGuiView.h"
#import "UDGuiGLView.h"
#import "UDGuiEditorViewController.h"
#import "UDSoftwareRenderer.h"
#import "rvGEWorkspace.h"
#import "rvGEWindowWrapper.h"
#import "idDict.h"
#import "idWindow.h"

/**
 * The Decl Browser against a real Doom 3 install (see UDDoom3InstallPath:
 * $UD_DOOM3_PATH, defaulting to /Volumes/ExtraSSD/games/DOOM 3). Every decl
 * here comes out of the retail pk4s through the ported file system.
 *
 * The install is only ever read: fs_savepath is a scratch directory, and
 * every case checks that base/ is byte-for-byte as it found it (in docker
 * the install is also mounted read-only). Where no install is present the
 * cases log that and return, as they do on CI.
 */
@interface UDDoom3WorkspaceTests : UDDeclBrowserTestCase
@property (nonatomic, copy) NSString *installPath;
@property (nonatomic, copy) NSString *savePath;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray *> *baseSnapshot;
@end

@implementation UDDoom3WorkspaceTests

/// Name -> [size, modification date] of everything directly in base/.
- (NSDictionary<NSString *, NSArray *> *)snapshotOfBase {
    NSString *base = [self.installPath stringByAppendingPathComponent:@"base"];
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:base error:NULL]) {
        NSDictionary *attributes = [[NSFileManager defaultManager]
            attributesOfItemAtPath:[base stringByAppendingPathComponent:name] error:NULL];
        snapshot[name] = @[attributes[NSFileSize] ?: @0, attributes[NSFileModificationDate] ?: [NSNull null]];
    }
    return snapshot;
}

- (void)setUp {
    [super setUp];
    self.installPath = UDDoom3InstallPath();
    if (self.installPath == nil) {
        NSLog(@"UDDoom3WorkspaceTests: no Doom 3 install (set UD_DOOM3_PATH); these cases check nothing here");
        return;
    }
    self.savePath = [self.scratchDirectory stringByAppendingPathComponent:@"save"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.savePath
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    self.baseSnapshot = [self snapshotOfBase];
}

- (void)tearDown {
    if (self.installPath != nil) {
        [super tearDown];
        XCTAssertEqualObjects([self snapshotOfBase], self.baseSnapshot,
                              @"the Doom 3 install must come out exactly as it went in");
        return;
    }
    [super tearDown];
}

- (UDWorkspaceWindowController *)openDoom3 {
    return [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:self.installPath
                                                                      savePath:self.savePath]];
}

#pragma mark - Browsing

- (void)testTheOutlineListsTheRetailDecls {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    NSOutlineView *outline = controller.outlineView;
    NSMutableSet *topLevel = [NSMutableSet set];
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        [topLevel addObject:[[outline itemAtRow:row] name]];
    }
    for (NSString *group in @[@"material", @"table", @"skin", @"sound", @"entityDef", @"mapDef", @"model", @"fx", @"particle", @"articulatedFigure", @"pda", @"email", @"audio", @"video", @"script", @"guis"]) {
        XCTAssertTrue([topLevel containsObject:group], @"the outline should have a %@ group; it has %@", group, topLevel);
    }

    NSArray<NSString *> *paths = [self expandedOutlinePathsInController:controller];
    NSUInteger pdas = [[paths filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'pda/'"]] count];
    XCTAssertGreaterThanOrEqual(pdas, 60U, @"pak000.pk4 ships 68 PDA files; the outline lists %lu PDAs", (unsigned long)pdas);
    for (NSString *path in @[@"pda/admin_moses", @"email/admin_moses_email_1", @"material/textures/base_wall/lfwall27d", @"entityDef/monster_zombie_fat", @"articulatedFigure/monster_zombie_fat", @"model/monster_zombie_fat", @"mapDef/game/mars_city1"]) {
        XCTAssertTrue([paths containsObject:path], @"the outline should list %@", path);
    }

    idDeclManager *declManager = ((UDWorkspaceDocument *)controller.document).workspace.declManager;
    NSUInteger materials = 0;
    for (id decl in [declManager declsOfType:DECL_MATERIAL forceParse:NO]) {
        (void)decl;
        materials++;
    }
    XCTAssertGreaterThan(materials, 1000U, @"the retail materials should all be indexed");
}

- (void)testTheNameFilterNarrowsTheOutline {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    NSUInteger everything = [self expandedOutlinePathsInController:controller].count;

    controller.nameFilterField.stringValue = @"*moses*";
    [controller nameFilterChanged:controller.nameFilterField];
    NSArray<NSString *> *filtered = [self expandedOutlinePathsInController:controller];

    XCTAssertLessThan(filtered.count, everything / 100, @"filtering on *moses* should leave a handful of rows");
    XCTAssertTrue([filtered containsObject:@"pda/admin_moses"], @"%@", filtered);
    XCTAssertTrue([filtered containsObject:@"email/admin_moses_email_3"], @"%@", filtered);
    for (NSString *path in filtered) {
        BOOL isLeafMatch = [path.lastPathComponent rangeOfString:@"moses" options:NSCaseInsensitiveSearch].location != NSNotFound;
        BOOL isGroup = ![path containsString:@"/"];
        XCTAssertTrue(isLeafMatch || isGroup, @"%@ does not match *moses*", path);
    }

    controller.nameFilterField.stringValue = @"";
    [controller nameFilterChanged:controller.nameFilterField];
    XCTAssertEqual([self expandedOutlinePathsInController:controller].count, everything,
                   @"clearing the filter should bring every row back");
}

- (void)testTheTextSearchFindsDeclsByContent {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    controller.textFilterField.stringValue = @"Martian Buddy";
    [controller textContainsFilterChanged:controller.textFilterField];

    NSOutlineView *results = controller.searchOutlineView;
    [results expandItem:nil expandChildren:YES];
    NSMutableArray *names = [NSMutableArray array];
    for (NSInteger row = 0; row < results.numberOfRows; row++) {
        id item = [results itemAtRow:row];
        [names addObject:[results.dataSource outlineView:results objectValueForTableColumn:results.tableColumns.firstObject byItem:item]];
    }
    XCTAssertTrue([names containsObject:@"email/admin_moses_email_1"],
                  @"the email that mentions Martian Buddy should be found; got %@", names);
}

- (void)testARetailMaterialOpensInTheMaterialEditor {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    UDBaseEditorViewController *editor = [self openOutlinePath:@"material/textures/base_wall/lfwall27d" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDMaterialEditorViewController class]], @"a material opens in its editor, not %@", editor);
    if (![editor isKindOfClass:[UDMaterialEditorViewController class]]) return;
    UDMaterialEditorViewController *material = (UDMaterialEditorViewController *)editor;
    XCTAssertGreaterThan(material.material.stages.count, 0U);
    XCTAssertNotNil(material.previewView.image, @"its first stage's image, from the paks: %@", material.previewLabel.stringValue);
    XCTAssertEqual(material.diagnosticStore.allDiagnostics.count, 0U, @"%@", [material.diagnosticStore.allDiagnostics valueForKey:@"message"]);

    // Lit by the game's own interaction.vfp: its bump, diffuse and specular.
    [material.tabView selectTabViewItemWithIdentifier:@"preview"];
    [material.materialPreview renderAtTime:0];
    XCTAssertEqualObjects(material.lightingLabel.stringValue, @"", @"interaction.vfp from pak000, run");
    NSBitmapImageRep *rep = (NSBitmapImageRep *)material.materialPreviewView.image.representations.firstObject;
    NSUInteger pixel[4], lit = 0;
    for (NSInteger y = 0; y < rep.pixelsHigh; y += 4) {
        for (NSInteger x = 0; x < rep.pixelsWide; x += 4) {
            [rep getPixel:pixel atX:x y:y];
            if (pixel[0] + pixel[1] + pixel[2] > 150) lit++;
        }
    }
    XCTAssertGreaterThan(lit, 50U, @"the wall, lit (lfwall27d has no ambient stage)");
}

- (void)testAPDAOpensInThePDAEditor {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    UDPDAEditorViewController *editor = [self openOutlinePath:@"pda/admin_moses" inController:controller];
    if (![editor isKindOfClass:[UDPDAEditorViewController class]]) {
        XCTFail(@"a pda decl should open in the PDA editor, not %@", editor);
        return;
    }
    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:editor.view].stringValue, @"Jonathan A. Moses");
    XCTAssertEqualObjects([self textFieldBoundTo:@"pdaName" inView:editor.view].stringValue, @"Jonathan Moses");
    XCTAssertEqualObjects([self textFieldBoundTo:@"ident" inView:editor.view].stringValue, @"2463-21");
    XCTAssertEqualObjects([self textFieldBoundTo:@"post" inView:editor.view].stringValue, @"Administration");

    NSArray *subjects = [editor.emailArrayController.arrangedObjects valueForKey:@"subject"];
    XCTAssertEqual(subjects.count, 3U, @"admin_moses has three emails");
    XCTAssertTrue([subjects containsObject:@"Free Stuff!!"], @"%@", subjects);
    XCTAssertTrue([subjects containsObject:@"Storage Cabinet"], @"%@", subjects);

    // Opening the same decl again re-uses its tab.
    NSUInteger tabs = [[self tabManagerOf:controller] allEditors].count;
    [self openOutlinePath:@"pda/admin_moses" inController:controller];
    XCTAssertEqual([[self tabManagerOf:controller] allEditors].count, tabs, @"re-selecting a decl should not open a second tab");
}

- (void)testARetailEntityDefInheritsThroughItsChain {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    UDEntityDefEditorViewController *editor = [self openOutlinePath:@"entityDef/monster_zombie_fat" inController:controller];
    if (![editor isKindOfClass:[UDEntityDefEditorViewController class]]) {
        XCTFail(@"an entityDef should open in the entityDef editor, not %@", editor);
        return;
    }
    XCTAssertEqualObjects(((NSTextField *)[self viewWithToolTip:@"inherit" inView:editor.view]).stringValue, @"zombie_default");
    NSArray *own = [editor.keyValuesController.arrangedObjects valueForKey:@"key"];
    XCTAssertTrue([own containsObject:@"scriptobject"], @"%@", own);
    NSArray *froms = [editor.inheritedController.arrangedObjects valueForKey:@"from"];
    XCTAssertTrue([froms containsObject:@"zombie_default"], @"its parent's pairs");
    XCTAssertGreaterThan([[NSSet setWithArray:froms] count], 1U, @"and further up its chain: %@", [NSSet setWithArray:froms]);
    XCTAssertEqual(editor.diagnosticStore.allDiagnostics.count, 0U, @"every entityDef it inherits is there: %@",
                   editor.diagnosticStore.allDiagnostics);
}

- (void)testEveryRetailSoundShaderParses {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    idDeclManager *declManager = ((UDWorkspaceDocument *)controller.document).workspace.declManager;
    NSUInteger shaders = 0;
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    for (idDeclBase *decl in [declManager declsOfType:DECL_SOUND forceParse:NO]) {
        NSMutableData *buffer = [NSMutableData data];
        [decl text:buffer];
        NSString *text = [[NSString alloc] initWithBytes:buffer.bytes length:buffer.length > 0 ? buffer.length - 1 : 0
                                                encoding:NSUTF8StringEncoding] ?: @"";
        for (UDDeclTextProblem *problem in [UDDeclSound ud_problemsParsingText:text name:[decl name] fileSystem:nil]) {
            [problems addObject:[NSString stringWithFormat:@"%@: %@", [decl name], problem]];
        }
        shaders++;
    }
    XCTAssertGreaterThan(shaders, 1000U, @"the retail sound shaders are indexed");
    // ParseShader gives up on these, and the engine makes them defaults:
    // stereo_omni is no keyword of it, nor "if", nor a folder for a sample.
    NSArray<NSString *> *rejected = [[problems valueForKey:@"description"] sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqual(rejected.count, 5U, @"%@", rejected);
    for (NSString *expected in @[@"teleport_in: warning line 7: unknown token 'stereo_omni'",
                                 @"teleport_lightning: warning line 5: unknown token 'stereo_omni'"]) {
        XCTAssertTrue([rejected containsObject:expected], @"%@ in %@", expected, rejected);
    }
}

- (void)testEveryRetailParticleParses {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    idDeclManager *declManager = ((UDWorkspaceDocument *)controller.document).workspace.declManager;
    NSUInteger particles = 0;
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    for (idDeclBase *decl in [declManager declsOfType:DECL_PARTICLE forceParse:NO]) {
        NSMutableData *buffer = [NSMutableData data];
        [decl text:buffer];
        NSString *text = [[NSString alloc] initWithBytes:buffer.bytes length:buffer.length > 0 ? buffer.length - 1 : 0
                                                encoding:NSUTF8StringEncoding] ?: @"";
        for (UDDeclTextProblem *problem in [UDDeclParticle ud_problemsParsingText:text name:[decl name] fileSystem:nil]) {
            [problems addObject:[NSString stringWithFormat:@"%@: %@", [decl name], problem]];
        }
        particles++;
    }
    XCTAssertGreaterThan(particles, 500U, @"the retail particles are indexed");
    // The one idDeclParticle::Parse gives up on, and the engine makes a
    // default: bfg_wallmark's stage says depthHack, which only a particle
    // may; the stage ends there, and the particle meets its "10".
    XCTAssertEqualObjects(problems, (@[@"bfg_wallmark: error line 3: unknown token depthHack\n",
                                       @"bfg_wallmark: warning line 3: bad token 10"]), @"%@", problems);
}

- (void)testEveryRetailFXParses {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    idDeclManager *declManager = ((UDWorkspaceDocument *)controller.document).workspace.declManager;
    NSUInteger fxs = 0;
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    for (idDeclBase *decl in [declManager declsOfType:DECL_FX forceParse:NO]) {
        NSMutableData *buffer = [NSMutableData data];
        [decl text:buffer];
        NSString *text = [[NSString alloc] initWithBytes:buffer.bytes length:buffer.length > 0 ? buffer.length - 1 : 0
                                                encoding:NSUTF8StringEncoding] ?: @"";
        for (UDDeclTextProblem *problem in [UDDeclFX ud_problemsParsingText:text name:[decl name] fileSystem:nil]) {
            [problems addObject:[NSString stringWithFormat:@"%@: %@", [decl name], problem]];
        }
        fxs++;
    }
    XCTAssertGreaterThan(fxs, 50U, @"the retail FX are indexed");
    XCTAssertEqual(problems.count, 0U, @"idDeclFX::Parse reads them all: %@", problems);
}

- (void)testEveryRetailMaterialIsReadAsTheEngineReadsItAndWrittenAsItWas {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    UDWorkspace *workspace = ((UDWorkspaceDocument *)controller.document).workspace;
    idDeclManager *declManager = workspace.declManager;
    NSUInteger materials = 0;
    NSMutableArray<NSString *> *defaulted = [NSMutableArray array];
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    for (idDeclBase *decl in [declManager declsOfType:DECL_MATERIAL forceParse:NO]) {
        NSMutableData *buffer = [NSMutableData data];
        [decl text:buffer];
        NSData *text = [buffer subdataWithRange:NSMakeRange(0, buffer.length > 0 ? buffer.length - 1 : 0)];
        NSString *string = [[NSString alloc] initWithData:text encoding:NSUTF8StringEncoding] ?:
                           [[NSString alloc] initWithData:text encoding:NSISOLatin1StringEncoding] ?: @"";
        UDMaterialParser *parser = [[UDMaterialParser alloc] initWithText:string name:[decl name] declManager:declManager];
        if (parser.defaulted) [defaulted addObject:[decl name]];
        for (UDDeclTextProblem *problem in parser.problems) {
            [warnings addObject:[NSString stringWithFormat:@"%@: %@", [decl name], problem.message]];
        }
        // What the model keeps of it is what it was, byte for byte.
        NSDictionary *values = [UDDeclMaterial ud_parseValuesFromText:text name:[decl name] fileName:nil lineNum:1
                                                           fileSystem:workspace.fileSystem error:NULL];
        NSData *written = [UDDeclMaterial ud_textByUnparsingName:[decl name] values:values error:NULL];
        NSString *body = [string substringFromIndex:MIN([string rangeOfString:@"{"].location, string.length)];
        NSString *writtenString = [[NSString alloc] initWithData:written encoding:NSUTF8StringEncoding];
        if (![writtenString isEqualToString:body]) [changed addObject:[decl name]];
        materials++;
    }
    XCTAssertGreaterThan(materials, 1000U, @"the retail materials are indexed");
    // What the engine itself says of retail: these it draws as the default
    // material.
    XCTAssertEqualObjects([defaulted sortedArrayUsingSelector:@selector(compare:)], (@[
        @"models/mapobjects/fuel_barrel/fbarrel", @"models/mapobjects/fuel_barrel/pbarrel_flare",
        @"models/mapobjects/hellcages/hellcagechain_", @"shaderdemos/shadowdrawlight", @"textures/common/nodrop",
        @"textures/decals/hellwind", @"textures/decals/wallsplat1", @"textures/hell/smokeblend",
        @"textures/object/cdplayer", @"textures/particles/bfgball", @"textures/sfx/flare_toggle",
        @"textures/sfx/flare_toggle2", @"textures/sfx/radiogoop_mix", @"video/noise"]));
    XCTAssertEqualObjects([warnings sortedArrayUsingSelector:@selector(compare:)], (@[
        @"models/mapobjects/fuel_barrel/fbarrel: unknown general material parameter 'flare' in 'models/mapobjects/fuel_barrel/fbarrel'",
        @"models/mapobjects/fuel_barrel/pbarrel_flare: unknown general material parameter 'flare' in 'models/mapobjects/fuel_barrel/pbarrel_flare'",
        @"models/mapobjects/hellcages/hellcagechain_: unknown token 'bumpmap' in material 'models/mapobjects/hellcages/hellcagechain_'",
        @"shaderdemos/shadowdrawlight: unknown token 'shadowDraw' in material 'shaderdemos/shadowdrawlight'",
        @"textures/common/nodrop: unknown general material parameter 'nodrop' in 'textures/common/nodrop'",
        @"textures/decals/hellwind: unknown token 'bugwings' in material 'textures/decals/hellwind'",
        @"textures/decals/wallsplat1: missing sort parameter",
        @"textures/hell/smokeblend: unknown token 'vertexblend' in material 'textures/hell/smokeblend'",
        @"textures/object/cdplayer: Bad term 'cdplayertable'",
        @"textures/object/cdplayer: expected ',' but found '['",
        @"textures/particles/bfgball: unknown general material parameter 'nomipmaps' in 'textures/particles/bfgball'",
        @"textures/sfx/flare_toggle2: Bad term 'red'",
        @"textures/sfx/flare_toggle: Bad term 'red'",
        @"textures/sfx/radiogoop_mix: unknown token 'inverse' in material 'textures/sfx/radiogoop_mix'",
        @"video/noise: unknown token 'noisemap' in material 'video/noise'"]));
    XCTAssertEqual(changed.count, 0U, @"written as it was read: %@", changed);
}

- (void)testEveryRetailArticulatedFigureParsesAndIsWrittenTheSameTwice {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    idDeclManager *declManager = ((UDWorkspaceDocument *)controller.document).workspace.declManager;
    NSUInteger figures = 0;
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    NSMutableArray<NSString *> *unstable = [NSMutableArray array];
    for (idDeclBase *decl in [declManager declsOfType:DECL_AF forceParse:NO]) {
        NSMutableData *buffer = [NSMutableData data];
        [decl text:buffer];
        NSData *text = [buffer subdataWithRange:NSMakeRange(0, buffer.length > 0 ? buffer.length - 1 : 0)];
        NSString *string = [[NSString alloc] initWithData:text encoding:NSUTF8StringEncoding] ?: @"";
        for (UDDeclTextProblem *problem in [UDDeclAF ud_problemsParsingText:string name:[decl name] fileSystem:nil]) {
            [problems addObject:[NSString stringWithFormat:@"%@: %@", [decl name], problem]];
        }
        // The writer's "%f" rounds what it writes (a 1.19e-08 is 0.000000),
        // as the engine's does; what it wrote it writes again the same.
        NSDictionary *values = [UDDeclAF ud_parseValuesFromText:text name:[decl name] fileName:nil lineNum:1 fileSystem:nil error:NULL];
        NSData *written = [UDDeclAF ud_textByUnparsingName:[decl name] values:values error:NULL];
        NSDictionary *again = [UDDeclAF ud_parseValuesFromText:written name:[decl name] fileName:nil lineNum:1 fileSystem:nil error:NULL];
        NSData *rewritten = [UDDeclAF ud_textByUnparsingName:[decl name] values:again error:NULL];
        if (![written isEqualToData:rewritten]) [unstable addObject:[decl name]];
        XCTAssertEqual([values[@"bodies"] count], [again[@"bodies"] count], @"%@", [decl name]);
        XCTAssertEqual([values[@"constraints"] count], [again[@"constraints"] count], @"%@", [decl name]);
        figures++;
    }
    XCTAssertGreaterThan(figures, 20U, @"the retail articulated figures are indexed");
    XCTAssertEqual(problems.count, 0U, @"idDeclAF::Parse reads them all: %@", problems);
    XCTAssertEqual(unstable.count, 0U, @"what RebuildTextSource's writers write, they write again the same: %@", unstable);
}

- (void)testEveryRetailFiguresBodiesAreOnItsModelsJoints {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    // Where the figure's model and its .md5mesh are there (retail lacks some
    // of both: env_hellcage_long's mesh, char_npc's modelDef), its bodies
    // are on the mesh's joints.
    UDWorkspace *workspace = ((UDWorkspaceDocument *)controller.document).workspace;
    NSUInteger checked = 0;
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (idDeclBase *decl in [workspace.declManager declsOfType:DECL_AF forceParse:NO]) {
        NSMutableData *buffer = [NSMutableData data];
        [decl text:buffer];
        NSData *text = [buffer subdataWithRange:NSMakeRange(0, buffer.length > 0 ? buffer.length - 1 : 0)];
        NSDictionary *values = [UDDeclAF ud_parseValuesFromText:text name:[decl name] fileName:nil lineNum:1 fileSystem:nil error:NULL];
        NSString *mesh = [UDMD5Mesh meshOfModelDef:values[@"model"] declManager:workspace.declManager];
        if (mesh == nil || [workspace.fileSystem readFile:mesh buffer:NULL timestamp:NULL error:NULL] < 0) continue;
        NSError *error = nil;
        NSArray<NSString *> *joints = [UDMD5Mesh jointNamesOfMeshAtPath:mesh fileSystem:workspace.fileSystem error:&error];
        if (joints == nil) {
            [missing addObject:[NSString stringWithFormat:@"%@: %@", mesh, error.localizedDescription]];
            continue;
        }
        // idRenderModelMD5::GetJointHandle's Icmp: any case.
        NSArray *lower = [joints valueForKey:@"lowercaseString"];
        for (UDAFBody *body in values[@"bodies"]) {
            if (![lower containsObject:body.jointName.lowercaseString]) {
                [missing addObject:[NSString stringWithFormat:@"%@: body %@'s joint %@", [decl name], body.name, body.jointName]];
            }
        }
        checked++;
    }
    XCTAssertGreaterThan(checked, 10U, @"figures whose meshes retail has");
    XCTAssertEqualObjects(missing, @[], @"the joints of each figure's model, as LoadModel reads them");
}

- (void)testEveryRetailGuiLoadsAndDraws {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    UDWorkspace *workspace = ((UDWorkspaceDocument *)controller.document).workspace;
    idUserInterfaceManager *manager = [[idUserInterfaceManager alloc] initWithFileSystem:workspace.fileSystem declManager:workspace.declManager];
    [manager managerInit];
    idFileList *list = [workspace.fileSystem listFilesTree:@"guis" extension:@".gui" sorted:YES inGameDir:nil error:NULL];
    NSUInteger guis = 0;
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    for (NSString *name in list.list) {
        @autoreleasepool {
            idUserInterfaceLocal *gui = [manager allocGui];
            if (![gui initFromFile:name]) {
                [problems addObject:[NSString stringWithFormat:@"%@: did not load", name]];
            }
            for (NSDictionary *d in gui.diagnostics) {
                [problems addObject:[NSString stringWithFormat:@"%@: %@:%@ %@", name, d[@"file"], d[@"line"], d[@"message"]]];
            }
            [gui activate:YES time:0];
            [manager.guiModel clear];
            [gui redraw:1000];
            [manager.guiModel emitFullScreen];
            if ([name isEqualToString:@"guis/mainmenu.gui"]) {
                XCTAssertNotNil([[gui getDesktop] findChildByName:@"LineH1"], @"the main menu's #include is read");
            }
            [manager deAlloc:gui];
            guis++;
        }
    }
    XCTAssertGreaterThan(guis, 500U, @"the retail GUIs are listed");
    XCTAssertEqual(problems.count, 0U, @"idWindow::Parse reads them all: %@", problems);
}

- (void)testTheRetailMainMenuRunsInTheViewer {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;
    [controller.window orderFront:nil];
    UDBaseEditorViewController *editor = [self openOutlinePath:@"guis/mainmenu.gui" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDGuiEditorViewController class]], @"the main menu opens running, not %@", editor);
    UDGuiEditorViewController *viewer = (UDGuiEditorViewController *)editor;
    UDGuiPlayer *player = viewer.player;
    XCTAssertEqual(player.diagnostics.count, 0u, @"%@", player.diagnostics);
    // as idSessionLocal::StartMenu leaves it when there is no intro to play
    player.playing = NO;
    [player sendNamedEvent:@"noIntro"];
    for (int i = 0; i < 120; i++) [player step];
    XCTAssertGreaterThan(player.triangles.count, 100u, @"the menu should be drawn");

    UDGuiGLView *gl = (UDGuiGLView *)viewer.guiView.glView;
    if (gl == nil) return;
#ifdef __APPLE__
    gl.wantsBestResolutionOpenGLSurface = NO;
#endif
    // the GUI at its own size, pixel for pixel
    [viewer.guiView setFrameSize:NSMakeSize(640, 480)];
    player.drawsPicture = YES;
    [player renderFrame];
    [viewer.guiView showFrame];
    NSBitmapImageRep *drawn = [gl readPicture];
    NSBitmapImageRep *expected = (NSBitmapImageRep *)player.frame.representations.firstObject;
    NSInteger off = 0, samples = 0;
    for (int y = 2; y < 480; y += 4) {
        for (int x = 2; x < 640; x += 4) {
            NSInteger gx = x * drawn.pixelsWide / 640, gy = y * drawn.pixelsHigh / 480;
            const uint8_t *a = drawn.bitmapData + gy * drawn.bytesPerRow + gx * 4;
            const uint8_t *b = expected.bitmapData + y * expected.bytesPerRow + x * 4;
            for (int k = 0; k < 3; k++) {
                if (abs((int)a[k] - (int)b[k]) > 16) off++;
                samples++;
            }
        }
    }
    XCTAssertLessThan(off, samples / 50, @"GL (%@) should draw the menu as the software renderer does: %ld of %ld off",
                      gl.glDescription, (long)off, (long)samples);
}

/// The window names of @a window and its children, depth first, with
/// their types as the editor writes them.
static void UDCollectWindows(idWindow *window, NSMutableArray<NSString *> *out) {
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:window];
    if (wrapper == nil || wrapper.deleted) return;
    [out addObject:[NSString stringWithFormat:@"%@ %@", [rvGEWindowWrapper stringFromWindowType:wrapper.windowType], [window getName]]];
    for (int i = 0; i < [wrapper childCount]; i++) {
        UDCollectWindows([wrapper childAtIndex:i], out);
    }
}

/// Whether a window of @a window's has a state key that is no name (a stray
/// token in its file: "*" of a "*/" whose "/*" is gone).
static BOOL UDHasStrayStateKeys(idWindow *window) {
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:window];
    if (wrapper == nil) return NO;
    NSCharacterSet *nameStart = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"];
    for (int i = 0; i < [wrapper.stateDict numKeyVals]; i++) {
        NSString *key = [wrapper.stateDict keyAtIndex:i];
        if (key.length == 0 || ![nameStart characterIsMember:[key characterAtIndex:0]]) return YES;
    }
    for (int i = 0; i < [wrapper childCount]; i++) {
        if (UDHasStrayStateKeys([wrapper childAtIndex:i])) return YES;
    }
    return NO;
}

- (void)testEveryRetailGuiIsWrittenBackAsTheEditorWritesIt {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;
    UDWorkspace *workspace = ((UDWorkspaceDocument *)controller.document).workspace;
    idUserInterfaceManager *manager = [[idUserInterfaceManager alloc] initWithFileSystem:workspace.fileSystem declManager:workspace.declManager];
    [manager managerInit];
    rvGEWorkspace *editor = [[rvGEWorkspace alloc] initWithManager:manager];
    idFileList *list = [workspace.fileSystem listFilesTree:@"guis" extension:@".gui" sorted:YES inGameDir:nil error:NULL];
    NSUInteger guis = 0;
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    NSMutableArray<NSString *> *strays = [NSMutableArray array];
    for (NSString *name in list.list) {
        @autoreleasepool {
            if (![editor loadFile:name]) {
                [problems addObject:[NSString stringWithFormat:@"%@: did not load", name]];
                continue;
            }
            NSMutableArray<NSString *> *windows = [NSMutableArray array];
            UDCollectWindows([editor.interface getDesktop], windows);
            BOOL stray = UDHasStrayStateKeys([editor.interface getDesktop]);
            NSString *written = editor.text;
            // read back from what was written, and written again
            if (![editor loadText:written path:name]) {
                [problems addObject:[NSString stringWithFormat:@"%@: what the editor wrote does not load", name]];
                continue;
            }
            for (NSDictionary *d in editor.interface.diagnostics) {
                [problems addObject:[NSString stringWithFormat:@"%@: written: %@:%@ %@", name, d[@"file"], d[@"line"], d[@"message"]]];
            }
            NSMutableArray<NSString *> *rereadWindows = [NSMutableArray array];
            UDCollectWindows([editor.interface getDesktop], rereadWindows);
            if (![rereadWindows isEqualToArray:windows]) {
                [problems addObject:[NSString stringWithFormat:@"%@: its windows are not the same read back (%lu, %lu)", name,
                                     (unsigned long)windows.count, (unsigned long)rereadWindows.count]];
            }
            // what the editor writes it reads back and writes the same, but
            // for a file with stray tokens: the main menu's "*/" in
            // OptionsGame (its "/*" commented out) is a state key "*", which,
            // written beside "visible", joins its expression when read back
            NSString *again = editor.text;
            if (stray) {
                [strays addObject:name];
            } else if (![again isEqualToString:written]) {
                [problems addObject:[NSString stringWithFormat:@"%@: written again, it is not the same", name]];
            }
            guis++;
        }
    }
    XCTAssertGreaterThan(guis, 500U, @"the retail GUIs are listed");
    XCTAssertEqual(problems.count, 0U, @"rvGEWorkspace::WriteWindow writes what reads back the same: %@", problems);
    XCTAssertEqualObjects(strays, @[@"guis/mainmenu.gui"], @"the retail GUIs with stray tokens");
}

#pragma mark - Editing

- (void)testEditingARetailPDASavesAnOverrideOutsideThePaks {
    if (self.installPath == nil) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;

    UDPDAEditorViewController *editor = [self openOutlinePath:@"pda/admin_moses" inController:controller];
    if (![editor isKindOfClass:[UDPDAEditorViewController class]]) {
        XCTFail(@"a pda decl should open in the PDA editor, not %@", editor);
        return;
    }

    [self typeText:@"Jonathan Q. Moses" intoField:[self textFieldBoundTo:@"fullName" inView:editor.view]];
    XCTAssertEqualObjects(editor.pda.fullName, @"Jonathan Q. Moses");
    XCTAssertTrue(editor.editorDocument.isDocumentEdited);

    [NSApp sendAction:@selector(saveDocument:) to:controller from:nil];
    [self spinUntil:^BOOL{ return NO; } timeout:0.1];
    XCTAssertFalse(editor.editorDocument.isDocumentEdited, @"Save should leave the tab clean");

    // The decl came out of pak000.pk4, so the save lands under fs_savepath
    // as a loose file the game loads ahead of the pak.
    NSString *override = [self.savePath stringByAppendingPathComponent:@"base/newpdas/admin_moses.pda"];
    NSString *text = [NSString stringWithContentsOfFile:override encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertNotNil(text, @"saving should write %@; the save path holds %@", override,
                    [[NSFileManager defaultManager] subpathsAtPath:self.savePath]);
    XCTAssertTrue([text containsString:@"Jonathan Q. Moses"], @"%@", text);
    XCTAssertFalse([text containsString:@"Jonathan A. Moses"], @"%@", text);
    for (NSString *email in @[@"admin_moses_email_1", @"admin_moses_email_2", @"admin_moses_email_3"]) {
        XCTAssertTrue([text containsString:email], @"the override must keep %@:\n%@", email, text);
    }

    // A fresh workspace over the same install and save path sees the edit.
    [self closeWorkspace:controller];
    UDWorkspaceWindowController *reopened = [self openDoom3];
    UDPDAEditorViewController *again = [self openOutlinePath:@"pda/admin_moses" inController:reopened];
    XCTAssertEqualObjects([self textFieldBoundTo:@"fullName" inView:again.view].stringValue, @"Jonathan Q. Moses");
    XCTAssertEqual([again.emailArrayController.arrangedObjects count], 3U, @"the emails come back with the PDA");
}

@end
