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

#import "idFile.h"
#import "idDeclParticle.h"
#import "UDLexer.h"
#import "UDWorkspace.h"
#import "idDeclMaterial.h"

typedef struct ParticleParmDesc {
    const char *name;
    int count;
    const char *desc;
} ParticleParmDesc_t;

const ParticleParmDesc_t ParticleDistributionDesc[] = {
    { "rect", 3, "" },
    { "cylinder", 4, "" },
    { "sphere", 3, "" }
};

const ParticleParmDesc_t ParticleDirectionDesc[] = {
    { "cone", 1, "" },
    { "outward", 1, "" },
};

const ParticleParmDesc_t ParticleOrientationDesc[] = {
    { "view", 0, "" },
    { "aimed", 2, "" },
    { "x", 0, "" },
    { "y", 0, "" },
    { "z", 0, "" }
};

const ParticleParmDesc_t ParticleCustomDesc[] = {
    { "standard", 0, "Standard" },
    { "helix", 5, "sizeX Y Z radialSpeed axialSpeed" },
    { "flies", 3, "radialSpeed axialSpeed size" },
    { "orbit", 2, "radius speed"},
    { "drip", 2, "something something" }
};

#define CustomParticleCount (sizeof(ParticleCustomDesc) / sizeof(ParticleParmDesc_t))

@interface idParticleStage ()
@property (weak, nonatomic, readwrite) idDeclParticle *particle;
@end

@interface idDeclParticle ()
@property (nonatomic, assign) float                    depthHack;
@end

@implementation idDeclParticle

-(size_t)size {
    return 0; //return sizeof( idDeclParticle );
}

/*
void idDeclParticle::GetStageBounds( idParticleStage *stage ) {
 
 stage->bounds.Clear();
 
 // this isn't absolutely guaranteed, but it should be close
 
 particleGen_t g;
 
 renderEntity_t    renderEntity;
 memset( &renderEntity, 0, sizeof( renderEntity ) );
 renderEntity.axis = mat3_identity;
 
 renderView_t    renderView;
 memset( &renderView, 0, sizeof( renderView ) );
 renderView.viewaxis = mat3_identity;
 
 g.renderEnt = &renderEntity;
 g.renderView = &renderView;
 g.origin.Zero();
 g.axis = mat3_identity;
 
 idRandom    steppingRandom;
 steppingRandom.SetSeed( 0 );
 
 // just step through a lot of possible particles as a representative sampling
 for ( int i = 0 ; i < 1000 ; i++ ) {
 g.random = g.originalRandom = steppingRandom;
 
 int    maxMsec = stage->particleLife * 1000;
 for ( int inCycleTime = 0 ; inCycleTime < maxMsec ; inCycleTime += 16 ) {
 
 // make sure we get the very last tic, which may make up an extreme edge
 if ( inCycleTime + 16 > maxMsec ) {
 inCycleTime = maxMsec - 1;
 }
 
 g.frac = (float)inCycleTime / ( stage->particleLife * 1000 );
 g.age = inCycleTime * 0.001f;
 
 // if the particle doesn't get drawn because it is faded out or beyond a kill region,
 // don't increment the verts
 
 idVec3    origin;
 stage->ParticleOrigin( &g, origin );
 stage->bounds.AddPoint( origin );
 }
 }
 
 // find the max size
 float    maxSize = 0;
 
 for ( float f = 0; f <= 1.0f; f += 1.0f / 64 ) {
 float size = stage->size.Eval( f, steppingRandom );
 float aspect = stage->aspect.Eval( f, steppingRandom );
 if ( aspect > 1 ) {
 size *= aspect;
 }
 if ( size > maxSize ) {
 maxSize = size;
 }
 }
 
 maxSize += 8;    // just for good measure
 // users can specify a per-stage bounds expansion to handle odd cases
 stage->bounds.ExpandSelf( maxSize + stage->boundsExpansion );
 }
 */

-(BOOL)parseParms:(idLexer *)src parms:(float *)parms maxParms:(int)maxParms error:(NSError **)error {
    idToken token;
    
    idToken_Init(&token);
    
    memset(parms, 0, maxParms * sizeof(*parms));
    int    count = 0;
    while( 1 ) {
        if (![src readTokenOnLine:&token error:error]) {
            return NO;
        }
        if (count == maxParms) {
            [src error:error format:@"too many parms on line"];
            return NO;
        }
        idToken_StripQuotes(&token);
        parms[count] = atof(token.text);
        count++;
    }
    
    return YES;
}

-(BOOL)parseParametric:(idLexer *)src parm:(idParticleParm *)parm error:(NSError **)error {
    idToken token;
    
    idToken_Init(&token);
    
    parm.table = nil;
    parm.from = parm.to = 0.0f;
    
    if (![src readToken:&token error:error]) {
        [src error:error format:@"not enough parameters"];
        return NO;
    }
    
    if (token.type == TT_NUMBER) { // FIXME: correct?
        // can have a to + 2nd parm
        parm.from = parm.to = idToken_FloatValue(&token);
        if ([src readToken:&token error:error]) {
            if (!strcasecmp(token.text, "to")) {
                if (![src readToken:&token error:error]) {
                    [src error:error format:@"missing second parameter"];
                    return NO;
                }
                parm.to = idToken_FloatValue(&token);
            } else {
                [src unreadToken:&token error:error];
            }
        }
    } else {
        // table
        parm.table = (idDeclTable *)[self.declManager findType:DECL_TABLE name:[NSString stringWithUTF8String:token.text] noCaching:NO error:error];
    }
    
    return YES;
}

-(BOOL)parseParticleStage:(idLexer *)src stage:(idParticleStage *)stage error:(NSError **)error {
    idToken token;
    
    [stage defaults];
    
    while (1) {
        if ([src hadError]) {
            break;
        }
        if (![src readToken:&token error:error]) {
            break;
        }
        if (!strcasecmp(token.text, "}")) {
            break;
        }
        if (!strcasecmp(token.text, "material")) {
            [src readToken:&token error:error];
            stage.material = [self.declManager findMaterial:[NSString stringWithUTF8String:token.text] error:nil];
            continue;
        }
        if (!strcasecmp(token.text, "count")) {
            int totalParticles = 0;
            if (![src parseInt:&totalParticles error:error]) {
                return NO;
            }
            stage.totalParticles = totalParticles;
            continue;
        }
        if (!strcasecmp(token.text, "time")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.particleLife = f;
            continue;
        }
        if (!strcasecmp(token.text, "cycles")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.cycles = f;
            continue;
        }
        if (!strcasecmp(token.text, "timeOffset")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.timeOffset = f;
            continue;
        }
        if (!strcasecmp(token.text, "deadTime")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.deadTime = f;
            continue;
        }
        if (!strcasecmp(token.text, "randomDistribution")) {
            BOOL b = NO;
            if (![src parseBool:&b error:error]) {
                return NO;
            }
            stage.randomDistribution = b;
            continue;
        }
        if (!strcasecmp(token.text, "bunching")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.spawnBunching = f;
            continue;
        }
        
        if (!strcasecmp(token.text, "distribution")) {
            [src readToken:&token error:error];
            if (!strcasecmp(token.text, "rect")) {
                stage.distributionType = PDIST_RECT;
            } else if (!strcasecmp(token.text, "cylinder")) {
                stage.distributionType = PDIST_CYLINDER;
            } else if (!strcasecmp(token.text, "sphere")) {
                stage.distributionType = PDIST_SPHERE;
            } else {
                [src error:error format:@"bad distribution type: %s\n", token.text];
            }
            idVec4 parms = idVec4Make(0, 0, 0, 0);
            if (![self parseParms:src parms:parms.v maxParms:sizeof(parms.v) / sizeof(parms.v[0]) error:error]) {
                return NO;
            }
            stage.distributionParms = parms;
            continue;
        }
        
        if (!strcasecmp(token.text, "direction")) {
            [src readToken:&token error:error];
            if (!strcasecmp(token.text, "cone")) {
                stage.directionType = PDIR_CONE;
            } else if (!strcasecmp(token.text, "outward")) {
                stage.directionType = PDIR_OUTWARD;
            } else {
                [src error:error format:@"bad direction type: %s\n", token.text];
            }
            idVec4 parms = idVec4Make(0, 0, 0, 0);
            if (![self parseParms:src parms:parms.v maxParms:sizeof(parms.v) / sizeof(parms.v[0]) error:error]) {
                return NO;
            }
            stage.directionParms = parms;
            continue;
        }
        
        if (!strcasecmp(token.text, "orientation")) {
            [src readToken:&token error:error];
            if (!strcasecmp(token.text, "view")) {
                stage.orientation = POR_VIEW;
            } else if (!strcasecmp(token.text, "aimed")) {
                stage.orientation = POR_AIMED;
            } else if (!strcasecmp(token.text, "x")) {
                stage.orientation = POR_X;
            } else if (!strcasecmp(token.text, "y")) {
                stage.orientation = POR_Y;
            } else if (!strcasecmp(token.text, "z")) {
                stage.orientation = POR_Z;
            } else {
                [src error:error format:@"bad orientation type: %s\n", token];
            }
            idVec4 parms = idVec4Make(0, 0, 0, 0);
            if (![self parseParms:src parms:parms.v maxParms:sizeof(parms.v) / sizeof(parms.v[0]) error:error]) {
                return NO;
            }
            stage.orientationParms = parms;
            continue;
        }
        
        if (!strcasecmp(token.text, "customPath")) {
            [src readToken:&token error:error];
            if (!strcasecmp(token.text, "standard")) {
                stage.customPathType = PPATH_STANDARD;
            } else if (!strcasecmp(token.text, "helix")) {
                stage.customPathType = PPATH_HELIX;
            } else if (!strcasecmp(token.text, "flies")) {
                stage.customPathType = PPATH_FLIES;
            } else if (!strcasecmp(token.text, "spherical")) {
                stage.customPathType = PPATH_ORBIT;
            } else {
                [src error:error format:@"bad path type: %s\n", token.text];
            }
            prtCustomPathParms_t parms;
            memset(&parms, 0, sizeof(parms));
            if (![self parseParms:src parms:parms.parms maxParms:sizeof(parms.parms) / sizeof(parms.parms[0]) error:error]) {
                return NO;
            }
            stage.customPathParms = parms;
            continue;
        }
        
        if (!strcasecmp(token.text, "speed")) {
            stage.speed = [[idParticleParm alloc] init];
            if (![self parseParametric:src parm:stage.speed error:error]) {
                return NO;
            }
            continue;
        }
        if (!strcasecmp(token.text, "rotation")) {
            stage.rotationSpeed = [[idParticleParm alloc] init];
            if (![self parseParametric:src parm:stage.rotationSpeed error:error]) {
                return NO;
            }
            continue;
        }
        if (!strcasecmp(token.text, "angle")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.initialAngle = f;
            continue;
        }
        if (!strcasecmp(token.text, "entityColor")) {
            BOOL b = NO;
            if (![src parseBool:&b error:error]) {
                return NO;
            }
            stage.entityColor = b;
            continue;
        }
        if (!strcasecmp(token.text, "size")) {
            stage.size = [[idParticleParm alloc] init];
            if (![self parseParametric:src parm:stage.size error:error]) {
                return NO;
            }
            continue;
        }
        if (!strcasecmp(token.text, "aspect")) {
            stage.aspect = [[idParticleParm alloc] init];
            if (![self parseParametric:src parm:stage.aspect error:error]) {
                return NO;
            }
            continue;
        }
        if (!strcasecmp(token.text, "fadeIn")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.fadeInFraction = f;
            continue;
        }
        if (!strcasecmp(token.text, "fadeOut")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.fadeOutFraction = f;
            continue;
        }
        if (!strcasecmp(token.text, "fadeIndex")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.fadeIndexFraction = f;
            continue;
        }
        if (!strcasecmp(token.text, "color")) {
            idVec4 color = idVec4Make(0, 0, 0, 0);
            if (![src parseFloat:&color.x error:error]) {
                return NO;
            }
            if (![src parseFloat:&color.y error:error]) {
                return NO;
            }
            if (![src parseFloat:&color.z error:error]) {
                return NO;
            }
            if (![src parseFloat:&color.w error:error]) {
                return NO;
            }
            stage.color = color;
            continue;
        }
        if (!strcasecmp(token.text, "fadeColor")) {
            idVec4 color = idVec4Make(0, 0, 0, 0);
            if (![src parseFloat:&color.x error:error]) {
                return NO;
            }
            if (![src parseFloat:&color.y error:error]) {
                return NO;
            }
            if (![src parseFloat:&color.z error:error]) {
                return NO;
            }
            if (![src parseFloat:&color.w error:error]) {
                return NO;
            }
            stage.fadeColor = color;
            continue;
        }
        if (!strcasecmp(token.text, "offset")) {
            idVec3 offset = idVec3Make(0, 0, 0);
            if (![src parseFloat:&offset.x error:error]) {
                return NO;
            }
            if (![src parseFloat:&offset.y error:error]) {
                return NO;
            }
            if (![src parseFloat:&offset.z error:error]) {
                return NO;
            }
            stage.offset = offset;
            continue;
        }
        if (!strcasecmp(token.text, "animationFrames")) {
            int i = 0;
            if (![src parseInt:&i error:error]) {
                return NO;
            }
            stage.animationFrames = i;
            continue;
        }
        if (!strcasecmp(token.text, "animationRate")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.animationRate = f;
            continue;
        }
        if (!strcasecmp(token.text, "boundsExpansion")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.boundsExpansion = f;
            continue;
        }
        if (!strcasecmp(token.text, "gravity")) {
            [src readToken:&token error:error];
            if (!strcasecmp(token.text, "world")) {
                stage.worldGravity = YES;
            } else {
                [src unreadToken:&token error:error];
            }
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.gravity = f;
            continue;
        }
        if (!strcasecmp(token.text, "softeningRadius")) { // #3878 soft particles
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            stage.softeningRadius = f;
            continue;
        }
        
        [src error:error format:@"unknown token %s\n", token.text];
        return NO;
    }
    
    // derive values
    stage.cycleMsec = (stage.particleLife + stage.deadTime) * 1000;
    
    return stage;
}

-(BOOL)parse:(NSMutableData *)text error:(NSError **)error {
    idLexer    *src;
    idToken    token;
    
    idToken_Init(&token);
    
    src = [[idLexer alloc] initWithFileSystem:self.declManager.workspace.fileSystem];
    if (![src loadMemory:text.bytes length:text.length-1 name:[self fileName] startLine:[self lineNum] error:error]) {
        return NO;
    }
    [src setFlags:DECL_LEXER_FLAGS];
    [src skipUntilString:@"{" error:error];
    
    self.depthHack = 0.0f;
    
    while (1) {
        if (![src readToken:&token error:error]) {
            break;
        }
        
        if (!strcasecmp(token.text, "}")) {
            break;
        }
        
        if (!strcasecmp(token.text, "{")) {
            idParticleStage *stage = [[idParticleStage alloc] init];
            if (![self parseParticleStage:src stage:stage error:error]) {
                [src warning:@"Particle stage parse failed"];
                [self makeDefault:error];
                return NO;
            }
            [self.stages addObject:stage];
            continue;
        }
        
        if (!strcasecmp(token.text, "depthHack")) {
            float f = 0.0f;
            if (![src parseFloat:&f error:error]) {
                return NO;
            }
            self.depthHack = f;
            continue;
        }
        
        [src warning:@"bad token %s", token.text];
        [self makeDefault:error];
        return NO;
    }
    
    //
    // calculate the bounds
    //
    /*
     bounds.Clear();
     for( int i = 0; i < stages.Num(); i++ ) {
     GetStageBounds( stages[i] );
     bounds.AddBounds( stages[i]->bounds );
     }
     
     if ( bounds.GetVolume() <= 0.1f ) {
     bounds = idBounds( vec3_origin ).Expand( 8.0f );
     }*/
    
    return YES;
}

-(void)freeData {
    [self.stages removeAllObjects];
}

-(NSString *)defaultDefinition {
    return
        @"{\n"
    @"\t"    @"{\n"
    @"\t\t"        @"material\t_default\n"
    @"\t\t"        @"count\t20\n"
    @"\t\t"        @"time\t\t1.0\n"
    @"\t"    @"}\n"
        @"}";
}

-(void)writeParticleParm:(idFile *)f parm:(idParticleParm *)parm name:(NSString *)name {

    [f writeFloatString:@"\t\t%s\t\t\t\t ", name.UTF8String];
    if (parm.table) {
        [f writeFloatString:@"%s\n", parm.table.name];
    } else {
        [f writeFloatString:@"\"%.3f\" ", parm.from];
        if (parm.from == parm.to) {
            [f writeFloatString:@"\n"];
        } else {
            [f writeFloatString:@" to \"%.3f\"\n", parm.to];
        }
    }
}

-(void)writeStage:(idFile *)f stage:(idParticleStage *)stage {

    int i;

    [f writeFloatString:@"\t{\n"];
    [f writeFloatString:@"\t\tcount\t\t\t\t%i\n", stage.totalParticles];
    [f writeFloatString:@"\t\tmaterial\t\t\t%s\n", stage.material.name.UTF8String];
    if (stage.animationFrames) {
        [f writeFloatString:@"\t\tanimationFrames \t%i\n", stage.animationFrames];
    }
    if (stage.animationRate) {
        [f writeFloatString:@"\t\tanimationRate \t\t%.3f\n", stage.animationRate];
    }
    [f writeFloatString:@"\t\ttime\t\t\t\t%.3f\n", stage.particleLife];
    [f writeFloatString:@"\t\tcycles\t\t\t\t%.3f\n", stage.cycles];
    if (stage.timeOffset) {
        [f writeFloatString:@"\t\ttimeOffset\t\t\t%.3f\n", stage.timeOffset];
    }
    if (stage.deadTime) {
        [f writeFloatString:@"\t\tdeadTime\t\t\t%.3f\n", stage.deadTime];
    }
    [f writeFloatString:@"\t\tbunching\t\t\t%.3f\n", stage.spawnBunching];

    [f writeFloatString:@"\t\tdistribution\t\t%s ", ParticleDistributionDesc[stage.distributionType].name];
    for (i = 0; i < ParticleDistributionDesc[stage.distributionType].count; i++) {
        [f writeFloatString:@"%.3f ", stage.distributionParms.v[i]];
    }
    [f writeFloatString:@"\n"];

    [f writeFloatString:@"\t\tdirection\t\t\t%s ", ParticleDirectionDesc[stage.directionType].name];
    for (i = 0; i < ParticleDirectionDesc[stage.directionType].count; i++) {
        [f writeFloatString:@"\"%.3f\" ", stage.directionParms.v[i]];
    }
    [f writeFloatString:@"\n"];

    [f writeFloatString:@"\t\torientation\t\t\t%s ", ParticleOrientationDesc[stage.orientation].name];
    for (i = 0; i < ParticleOrientationDesc[stage.orientation].count; i++) {
        [f writeFloatString:@"%.3f ", stage.orientationParms.v[i]];
    }
    [f writeFloatString:@"\n"];

    if (stage.customPathType != PPATH_STANDARD) {
        [f writeFloatString:@"\t\tcustomPath %s ", ParticleCustomDesc[stage.customPathType].name];
        for (i = 0; i < ParticleCustomDesc[stage.customPathType].count; i++) {
            [f writeFloatString:@"%.3f ", stage.customPathParms.parms[i]];
        }
        [f writeFloatString:@"\n"];
    }

    if (stage.entityColor) {
        [f writeFloatString:@"\t\tentityColor\t\t\t1\n"];
    }

    [self writeParticleParm:f parm:stage.speed name:@"speed"];
    [self writeParticleParm:f parm:stage.size name:@"size"];
    [self writeParticleParm:f parm:stage.aspect name:@"aspect"];

    if (stage.rotationSpeed.from) {
        [self writeParticleParm:f parm:stage.rotationSpeed name:@"rotation"];
    }

    if (stage.initialAngle) {
        [f writeFloatString:@"\t\tangle\t\t\t\t%.3f\n", stage.initialAngle];
    }

    [f writeFloatString:@"\t\trandomDistribution\t\t\t\t%i\n", (int)(stage.randomDistribution)];
    [f writeFloatString:@"\t\tboundsExpansion\t\t\t\t%.3f\n", stage.boundsExpansion];


    [f writeFloatString:@"\t\tfadeIn\t\t\t\t%.3f\n", stage.fadeInFraction];
    [f writeFloatString:@"\t\tfadeOut\t\t\t\t%.3f\n", stage.fadeOutFraction];
    [f writeFloatString:@"\t\tfadeIndex\t\t\t\t%.3f\n", stage.fadeIndexFraction];

    [f writeFloatString:@"\t\tcolor \t\t\t\t%.3f %.3f %.3f %.3f\n", stage.color.x, stage.color.y, stage.color.z, stage.color.w];
    [f writeFloatString:@"\t\tfadeColor \t\t\t%.3f %.3f %.3f %.3f\n", stage.fadeColor.x, stage.fadeColor.y, stage.fadeColor.z, stage.fadeColor.w];

    [f writeFloatString:@"\t\toffset \t\t\t\t%.3f %.3f %.3f\n", stage.offset.x, stage.offset.y, stage.offset.z];
    [f writeFloatString:@"\t\tgravity \t\t\t"];
    if (stage.worldGravity) {
        [f writeFloatString:@"world "];
    }
    [f writeFloatString:@"%.3f\n", stage.gravity];
    [f writeFloatString:@"\t}\n"];
}

-(BOOL)rebuildTextSource {
    idFile_Memory *f;
    
    f = [[idFile_Memory alloc] initWithFileSystem:self.declManager.workspace.fileSystem];
    
    [f writeFloatString:@"\n\n/*\n"
        "\tGenerated by the Particle Editor.\n"
        "\tTo use the particle editor, launch the game and type 'editParticles' on the console.\n"
        "*/\n"];

    [f writeFloatString:@"particle %s {\n", [self name].UTF8String];

    if (self.depthHack) {
        [f writeFloatString:@"\tdepthHack\t%f\n", self.depthHack];
    }

    for (int i = 0; i < self.stages.count; i++ ) {
        [self writeStage:f stage:[self.stages objectAtIndex:i]];
    }

    [f writeFloatString:@"}"];
    char eof = 0;
    [f write:&eof length:sizeof(eof) error:nil];

    NSMutableData *data = [[NSMutableData alloc] initWithBytesNoCopy:f.dataPtr length:f.length freeWhenDone:NO];
    [self setText:data];

    return YES;
}

-(BOOL)save:(NSString *)fileName {
    [self rebuildTextSource];
    if (fileName) {
        [self.declManager createNewDecl:DECL_PARTICLE name:[self name] fileName:fileName];
    }
    [self replaceSourceFileText:nil];
    return YES;
}

-(int)numStages {
    return (int)self.stages.count;
}

-(idParticleStage *)stageByIndex:(int)index {
    return [self.stages objectAtIndex:index];
}

-(void)addStage:(idParticleStage *)stage {
    [self.stages addObject:stage];
}

-(void)removeStage:(idParticleStage *)stage {
    NSInteger index = [self.stages indexOfObjectIdenticalTo:stage];
    if (index != NSNotFound) {
        [self.stages removeObjectAtIndex:index];
    }
}

-(void)insertStage:(idParticleStage *)stage beforeStage:(idParticleStage *)anchor {
    NSInteger index = anchor != nil ? [self.stages indexOfObjectIdenticalTo:anchor] : self.stages.count - 1;
    if (index == NSNotFound) {
        index = self.stages.count - 1;
    }
    [self.stages insertObject:stage atIndex:index];
}

-(void)moveStage:(idParticleStage *)stage beforeStage:(idParticleStage *)anchor {
    [self.stages removeObjectIdenticalTo:stage];
    NSInteger index = anchor != nil ? [self.stages indexOfObjectIdenticalTo:anchor] : self.stages.count - 1;
    if (index == NSNotFound) {
        index = self.stages.count - 1;
    }
    [self.stages insertObject:stage atIndex:index];
}

@end

/*
====================================================================================

idParticleParm

====================================================================================
*/

@implementation idParticleParm

-(instancetype)init {
    self = [super init];
    if (self) {
        // nop
    }
    return self;
}

-(void)copyFrom:(idParticleParm *)p {
    self.to = p.to;
    self.from = p.from;
    self.table = p.table;
}
/*
-(float)eval:(float)frac random:(idRandom *)rand {
    if (_table) {
        return [_table tableLookup:frac];
    }
    return from + frac * (to - from);
}

-(float)integrate:(float)frac random:(idRandom *)rand {
    if (_table) {
        //common->Printf( "idParticleParm::Integrate: can't integrate tables\n" );
        return 0;
    }
    return (from + frac * (to - from) * 0.5f) * frac;
}
*/
@end

/*
====================================================================================

idParticleStage

====================================================================================
*/
@implementation idParticleStage

-(instancetype)init {
    self = [super init];
    if (self) {
        self.material = NULL;
        self.totalParticles = 0;
        self.cycles = 0.0f;
        self.cycleMsec = 0;
        self.spawnBunching = 0.0f;
        self.particleLife = 0.0f;
        self.timeOffset = 0.0f;
        self.deadTime = 0.0f;
        self.distributionType = PDIST_RECT;
        self.distributionParms = idVec4Make(0, 0, 0, 0);
        self.directionType = PDIR_CONE;
        self.directionParms = idVec4Make(0, 0, 0, 0);
        self.speed = [[idParticleParm alloc] init];
        self.gravity = 0.0f;
        self.worldGravity = NO;
        self.customPathType = PPATH_STANDARD;
        {
            prtCustomPathParms_t p;
            p.parms[0] = p.parms[1] = p.parms[2] = p.parms[3] = 0.0f;
            p.parms[4] = p.parms[5] = p.parms[6] = p.parms[7] = 0.0f;
            self.customPathParms = p;
        }
        self.offset = idVec3Make(0, 0, 0);
        self.animationFrames = 0;
        self.animationRate = 0.0f;
        self.randomDistribution = YES;
        self.entityColor = NO;
        self.initialAngle = 0.0f;
        self.rotationSpeed = [[idParticleParm alloc] init];
        self.orientation = POR_VIEW;
        self.orientationParms = idVec4Make(0, 0, 0, 0);
        self.size = [[idParticleParm alloc] init];
        self.aspect = [[idParticleParm alloc] init];
        self.color = idVec4Make(0, 0, 0, 0);
        self.fadeColor = idVec4Make(0, 0, 0, 0);
        self.fadeInFraction = 0.0f;
        self.fadeOutFraction = 0.0f;
        self.fadeIndexFraction = 0.0f;
        self.hidden = NO;
        self.boundsExpansion = 0.0f;
        
        idBoundsClear(&_bounds);
        
        self.softeningRadius = -2.0f;    // -2 means "auto" - #3878 soft particles
    }
    return self;
}

-(void)defaults {
    self.material = [self.particle.declManager findMaterial:@"_default" error:nil];
    self.totalParticles = 100;
    self.spawnBunching = 1.0f;
    self.particleLife = 1.5f;
    self.timeOffset = 0.0f;
    self.deadTime = 0.0f;
    self.distributionType = PDIST_RECT;
    self.distributionParms = idVec4Make(8, 8, 8, 0);
    self.directionType = PDIR_CONE;
    self.directionParms = idVec4Make(90, 0, 0, 0);
    self.orientation = POR_VIEW;
    self.orientationParms = idVec4Make(0, 0, 0, 0);
    self.speed.from = 150.0f;
    self.speed.to = 150.0f;
    self.speed.table = nil;
    self.gravity = 1.0f;
    self.worldGravity = NO;
    self.customPathType = PPATH_STANDARD;
    {
        prtCustomPathParms_t p;
        
        p.parms[0] = 0.0f;
        p.parms[1] = 0.0f;
        p.parms[2] = 0.0f;
        p.parms[3] = 0.0f;
        p.parms[4] = 0.0f;
        p.parms[5] = 0.0f;
        p.parms[6] = 0.0f;
        p.parms[7] = 0.0f;
        self.customPathParms = p;
    }
    self.offset = idVec3Make(0, 0, 0);
    self.animationFrames = 0;
    self.animationRate = 0.0f;
    self.initialAngle = 0.0f;
    self.rotationSpeed.from = 0.0f;
    self.rotationSpeed.to = 0.0f;
    self.rotationSpeed.table = nil;
    self.size.from = 4.0f;
    self.size.to = 4.0f;
    self.size.table = nil;
    self.aspect.from = 1.0f;
    self.aspect.to = 1.0f;
    self.aspect.table = nil;
    self.color = idVec4Make(1, 1, 1, 1);
    self.fadeColor = idVec4Make(0, 0, 0, 0);
    self.fadeInFraction = 0.1f;
    self.fadeOutFraction = 0.25f;
    self.fadeIndexFraction = 0.0f;
    self.boundsExpansion = 0.0f;
    self.randomDistribution = YES;
    self.entityColor = NO;
    self.cycleMsec = (self.particleLife + self.deadTime) * 1000;
    self.softeningRadius = -2.0f;    // -2 means "auto" - #3878 soft particles
}

/*
// includes trails and cross faded animations
int idParticleStage::NumQuadsPerParticle() const {
    int    count = 1;

    if ( orientation == POR_AIMED ) {
        int    trails = idMath::Ftoi( orientationParms[0] );
        // each trail stage will add an extra quad
        count *= ( 1 + trails );
    }

    // if we are doing strip-animation, we need to double the number and cross fade them
    if ( animationFrames > 1 ) {
        count *= 2;
    }

    return count;
}

void idParticleStage::ParticleOrigin( particleGen_t *g, idVec3 &origin ) const {
    if ( customPathType == PPATH_STANDARD ) {
        //
        // find intial origin distribution
        //
        float radiusSqr, angle1, angle2;

        switch( distributionType ) {
            case PDIST_RECT: {    // ( sizeX sizeY sizeZ )
                origin[0] = ( ( randomDistribution ) ? g->random.CRandomFloat() : 1.0f ) * distributionParms[0];
                origin[1] = ( ( randomDistribution ) ? g->random.CRandomFloat() : 1.0f ) * distributionParms[1];
                origin[2] = ( ( randomDistribution ) ? g->random.CRandomFloat() : 1.0f ) * distributionParms[2];
                break;
            }
            case PDIST_CYLINDER: {    // ( sizeX sizeY sizeZ ringFraction )
                angle1 = ( ( randomDistribution ) ? g->random.CRandomFloat() : 1.0f ) * idMath::TWO_PI;

                idMath::SinCos16( angle1, origin[0], origin[1] );
                origin[2] = ( ( randomDistribution ) ? g->random.CRandomFloat() : 1.0f );

                // reproject points that are inside the ringFraction to the outer band
                if ( distributionParms[3] > 0.0f ) {
                    radiusSqr = origin[0] * origin[0] + origin[1] * origin[1];
                    if ( radiusSqr < distributionParms[3] * distributionParms[3] ) {
                        // if we are inside the inner reject zone, rescale to put it out into the good zone
                        float f = sqrt( radiusSqr ) / distributionParms[3];
                        float invf = 1.0f / f;
                        float newRadius = distributionParms[3] + f * ( 1.0f - distributionParms[3] );
                        float rescale = invf * newRadius;

                        origin[0] *= rescale;
                        origin[1] *= rescale;
                    }
                }
                origin[0] *= distributionParms[0];
                origin[1] *= distributionParms[1];
                origin[2] *= distributionParms[2];
                break;
            }
            case PDIST_SPHERE: {    // ( sizeX sizeY sizeZ ringFraction )
                // iterating with rejection is the only way to get an even distribution over a sphere
                if ( randomDistribution ) {
                    do {
                        origin[0] = g->random.CRandomFloat();
                        origin[1] = g->random.CRandomFloat();
                        origin[2] = g->random.CRandomFloat();
                        radiusSqr = origin[0] * origin[0] + origin[1] * origin[1] + origin[2] * origin[2];
                    } while( radiusSqr > 1.0f );
                } else {
                    origin.Set( 1.0f, 1.0f, 1.0f );
                    radiusSqr = 3.0f;
                }

                if ( distributionParms[3] > 0.0f ) {
                    // we could iterate until we got something that also satisfied ringFraction,
                    // but for narrow rings that could be a lot of work, so reproject inside points instead
                    if ( radiusSqr < distributionParms[3] * distributionParms[3] ) {
                        // if we are inside the inner reject zone, rescale to put it out into the good zone
                        float f = sqrt( radiusSqr ) / distributionParms[3];
                        float invf = 1.0f / f;
                        float newRadius = distributionParms[3] + f * ( 1.0f - distributionParms[3] );
                        float rescale = invf * newRadius;

                        origin[0] *= rescale;
                        origin[1] *= rescale;
                        origin[2] *= rescale;
                    }
                }
                origin[0] *= distributionParms[0];
                origin[1] *= distributionParms[1];
                origin[2] *= distributionParms[2];
                break;
            }
        }

        // offset will effect all particle origin types
        // add this before the velocity and gravity additions
        origin += offset;

        //
        // add the velocity over time
        //
        idVec3    dir;

        switch( directionType ) {
            case PDIR_CONE: {
                // angle is the full angle, so 360 degrees is any spherical direction
                angle1 = g->random.CRandomFloat() * directionParms[0] * idMath::M_DEG2RAD;
                angle2 = g->random.CRandomFloat() * idMath::PI;

                float s1, c1, s2, c2;
                idMath::SinCos16( angle1, s1, c1 );
                idMath::SinCos16( angle2, s2, c2 );

                dir[0] = s1 * c2;
                dir[1] = s1 * s2;
                dir[2] = c1;
                break;
            }
            case PDIR_OUTWARD: {
                dir = origin;
                dir.Normalize();
                dir[2] += directionParms[0];
                break;
            default:
                common->Error( "idParticleStage::ParticleOrigin: bad direction" );
                return;
            }
        }

        // add speed
        float iSpeed = speed.Integrate( g->frac, g->random );
        origin += dir * iSpeed * particleLife;

    } else {
        //
        // custom paths completely override both the origin and velocity calculations, but still
        // use the standard gravity
        //
        float angle1, angle2, speed1, speed2;
        switch( customPathType ) {
            case PPATH_HELIX: {        // ( sizeX sizeY sizeZ radialSpeed axialSpeed )
                speed1 = g->random.CRandomFloat();
                speed2 = g->random.CRandomFloat();
                angle1 = g->random.RandomFloat() * idMath::TWO_PI + customPathParms[3] * speed1 * g->age;

                float s1, c1;
                idMath::SinCos16( angle1, s1, c1 );

                origin[0] = c1 * customPathParms[0];
                origin[1] = s1 * customPathParms[1];
                origin[2] = g->random.RandomFloat() * customPathParms[2] + customPathParms[4] * speed2 * g->age;
                break;
            }
            case PPATH_FLIES: {        // ( radialSpeed axialSpeed size )
                speed1 = idMath::ClampFloat( 0.4f, 1.0f, g->random.CRandomFloat() );
                speed2 = idMath::ClampFloat( 0.4f, 1.0f, g->random.CRandomFloat() );
                angle1 = g->random.RandomFloat() * idMath::PI * 2 + customPathParms[0] * speed1 * g->age;
                angle2 = g->random.RandomFloat() * idMath::PI * 2 + customPathParms[1] * speed1 * g->age;

                float s1, c1, s2, c2;
                idMath::SinCos16( angle1, s1, c1 );
                idMath::SinCos16( angle2, s2, c2 );

                origin[0] = c1 * c2;
                origin[1] = s1 * c2;
                origin[2] = -s2;
                origin *= customPathParms[2];
                break;
            }
            case PPATH_ORBIT: {        // ( radius speed axis )
                angle1 = g->random.RandomFloat() * idMath::TWO_PI + customPathParms[1] * g->age;

                float s1, c1;
                idMath::SinCos16( angle1, s1, c1 );

                origin[0] = c1 * customPathParms[0];
                origin[1] = s1 * customPathParms[0];
                origin.ProjectSelfOntoSphere( customPathParms[0] );
                break;
            }
            case PPATH_DRIP: {        // ( speed )
                origin[0] = 0.0f;
                origin[1] = 0.0f;
                origin[2] = -( g->age * customPathParms[0] );
                break;
            }
            default: {
                common->Error( "idParticleStage::ParticleOrigin: bad customPathType" );
            }
        }

        origin += offset;
    }

    // adjust for the per-particle smoke offset
    origin *= g->axis;
    origin += g->origin;

    // add gravity after adjusting for axis
    if ( worldGravity ) {
        idVec3 gra( 0, 0, -gravity );
        gra *= g->renderEnt->axis.Transpose();
        origin += gra * g->age * g->age;
    } else {
        origin[2] -= gravity * g->age * g->age;
    }
}

int    idParticleStage::ParticleVerts( particleGen_t *g, idVec3 origin, idDrawVert *verts ) const {
    float    psize = size.Eval( g->frac, g->random );
    float    paspect = aspect.Eval( g->frac, g->random );

    float    width = psize;
    float    height = psize * paspect;

    idVec3    left, up;

    if ( orientation == POR_AIMED ) {
        // reset the values to an earlier time to get a previous origin
        idRandom    currentRandom = g->random;
        float        currentAge = g->age;
        float        currentFrac = g->frac;
        idDrawVert *verts_p = verts;
        idVec3        stepOrigin = origin;
        idVec3        stepLeft;
        int            numTrails = idMath::Ftoi( orientationParms[0] );
        float        trailTime = orientationParms[1];

        stepLeft.Zero();

        if ( trailTime == 0 ) {
            trailTime = 0.5f;
        }

        float height = 1.0f / ( 1 + numTrails );
        float t = 0;

        for ( int i = 0 ; i <= numTrails ; i++ ) {
            g->random = g->originalRandom;
            g->age = currentAge - ( i + 1 ) * trailTime / ( numTrails + 1 );    // time to back up
            g->frac = g->age / particleLife;

            idVec3    oldOrigin;
            ParticleOrigin( g, oldOrigin );

            up = stepOrigin - oldOrigin;    // along the direction of travel

            idVec3    forwardDir;
            g->renderEnt->axis.ProjectVector( g->renderView->viewaxis[0], forwardDir );

            up -= ( up * forwardDir ) * forwardDir;

            up.Normalize();


            left = up.Cross( forwardDir );
            left *= psize;

            verts_p[0] = verts[0];
            verts_p[1] = verts[1];
            verts_p[2] = verts[2];
            verts_p[3] = verts[3];

            if ( i == 0 ) {
                verts_p[0].xyz = stepOrigin - left;
                verts_p[1].xyz = stepOrigin + left;
            } else {
                verts_p[0].xyz = stepOrigin - stepLeft;
                verts_p[1].xyz = stepOrigin + stepLeft;
            }
            verts_p[2].xyz = oldOrigin - left;
            verts_p[3].xyz = oldOrigin + left;

            // modify texcoords
            verts_p[0].st[0] = verts[0].st[0];
            verts_p[0].st[1] = t;

            verts_p[1].st[0] = verts[1].st[0];
            verts_p[1].st[1] = t;

            verts_p[2].st[0] = verts[2].st[0];
            verts_p[2].st[1] = t+height;

            verts_p[3].st[0] = verts[3].st[0];
            verts_p[3].st[1] = t+height;

            t += height;

            verts_p += 4;

            stepOrigin = oldOrigin;
            stepLeft = left;
        }

        g->random = currentRandom;
        g->age = currentAge;
        g->frac = currentFrac;

        return 4 * (numTrails+1);
    }

    //
    // constant rotation
    //
    float    angle;

    angle = ( initialAngle ) ? initialAngle : 360 * g->random.RandomFloat();

    float    angleMove = rotationSpeed.Integrate( g->frac, g->random ) * particleLife;
    // have hald the particles rotate each way
    if ( g->index & 1 ) {
        angle += angleMove;
    } else {
        angle -= angleMove;
    }

    angle = angle / 180 * idMath::PI;
    float c = idMath::Cos16( angle );
    float s = idMath::Sin16( angle );

    if ( orientation  == POR_Z ) {
        // oriented in entity space
        left[0] = s;
        left[1] = c;
        left[2] = 0;
        up[0] = c;
        up[1] = -s;
        up[2] = 0;
    } else if ( orientation == POR_X ) {
        // oriented in entity space
        left[0] = 0;
        left[1] = c;
        left[2] = s;
        up[0] = 0;
        up[1] = -s;
        up[2] = c;
    } else if ( orientation == POR_Y ) {
        // oriented in entity space
        left[0] = c;
        left[1] = 0;
        left[2] = s;
        up[0] = -s;
        up[1] = 0;
        up[2] = c;
    } else {
        // oriented in viewer space
        idVec3    entityLeft, entityUp;

        g->renderEnt->axis.ProjectVector( g->renderView->viewaxis[1], entityLeft );
        g->renderEnt->axis.ProjectVector( g->renderView->viewaxis[2], entityUp );

        left = entityLeft * c + entityUp * s;
        up = entityUp * c - entityLeft * s;
    }

    left *= width;
    up *= height;

    verts[0].xyz = origin - left + up;
    verts[1].xyz = origin + left + up;
    verts[2].xyz = origin - left - up;
    verts[3].xyz = origin + left - up;

    return 4;
}

void idParticleStage::ParticleTexCoords( particleGen_t *g, idDrawVert *verts ) const {
    float    s, width;
    float    t, height;

    if ( animationFrames > 1 ) {
        width = 1.0f / animationFrames;
        float    floatFrame;
        if ( animationRate ) {
            // explicit, cycling animation
            floatFrame = g->age * animationRate;
        } else {
            // single animation cycle over the life of the particle
            floatFrame = g->frac * animationFrames;
        }
        int    intFrame = (int)floatFrame;
        g->animationFrameFrac = floatFrame - intFrame;
        s = width * intFrame;
    } else {
        s = 0.0f;
        width = 1.0f;
    }

    t = 0.0f;
    height = 1.0f;

    verts[0].st[0] = s;
    verts[0].st[1] = t;

    verts[1].st[0] = s+width;
    verts[1].st[1] = t;

    verts[2].st[0] = s;
    verts[2].st[1] = t+height;

    verts[3].st[0] = s+width;
    verts[3].st[1] = t+height;
}

void idParticleStage::ParticleColors( particleGen_t *g, idDrawVert *verts ) const {
    float    fadeFraction = 1.0f;

    // most particles fade in at the beginning and fade out at the end
    if ( g->frac < fadeInFraction ) {
        fadeFraction *= ( g->frac / fadeInFraction );
    }
    if ( 1.0f - g->frac < fadeOutFraction ) {
        fadeFraction *= ( ( 1.0f - g->frac ) / fadeOutFraction );
    }

    // individual gun smoke particles get more and more faded as the
    // cycle goes on (note that totalParticles won't be correct for a surface-particle deform)
    if ( fadeIndexFraction ) {
        float    indexFrac = ( totalParticles - g->index ) / (float)totalParticles;
        if ( indexFrac < fadeIndexFraction ) {
            fadeFraction *= indexFrac / fadeIndexFraction;
        }
    }

    for ( int i = 0 ; i < 4 ; i++ ) {
        float    fcolor = ( ( entityColor ) ? g->renderEnt->shaderParms[i] : color[i] ) * fadeFraction + fadeColor[i] * ( 1.0f - fadeFraction );
        int        icolor = idMath::FtoiFast( fcolor * 255.0f );
        if ( icolor < 0 ) {
            icolor = 0;
        } else if ( icolor > 255 ) {
            icolor = 255;
        }
        verts[0].color[i] =
        verts[1].color[i] =
        verts[2].color[i] =
        verts[3].color[i] = icolor;
    }
}*/

/*
================
idParticleStage::CreateParticle

Returns 0 if no particle is created because it is completely faded out
Returns 4 if a normal quad is created
Returns 8 if two cross faded quads are created

Vertex order is:

0 1
2 3
================
*//*
int idParticleStage::CreateParticle( particleGen_t *g, idDrawVert *verts ) const {
    idVec3    origin;

    verts[0].Clear();
    verts[1].Clear();
    verts[2].Clear();
    verts[3].Clear();

    ParticleColors( g, verts );

    // if we are completely faded out, kill the particle
    if ( verts[0].color[0] == 0 && verts[0].color[1] == 0 && verts[0].color[2] == 0 && verts[0].color[3] == 0 ) {
        return 0;
    }

    ParticleOrigin( g, origin );

    ParticleTexCoords( g, verts );

    int    numVerts = ParticleVerts( g, origin, verts );

    if ( animationFrames <= 1 ) {
        return numVerts;
    }

    // if we are doing strip-animation, we need to double the quad and cross fade it
    float    width = 1.0f / animationFrames;
    float    frac = g->animationFrameFrac;
    float    iFrac = 1.0f - frac;
    for ( int i = 0 ; i < numVerts ; i++ ) {
        verts[numVerts + i] = verts[i];

        verts[numVerts + i].st[0] += width;

        verts[numVerts + i].color[0] *= frac;
        verts[numVerts + i].color[1] *= frac;
        verts[numVerts + i].color[2] *= frac;
        verts[numVerts + i].color[3] *= frac;

        verts[i].color[0] *= iFrac;
        verts[i].color[1] *= iFrac;
        verts[i].color[2] *= iFrac;
        verts[i].color[3] *= iFrac;
    }

    return numVerts * 2;
}*/

-(NSString *)customPathName {
    int index = (self.customPathType < CustomParticleCount) ? self.customPathType : 0;
    return [NSString stringWithUTF8String:ParticleCustomDesc[index].name];
}

-(NSString *)customPathDesc {
    int index = (self.customPathType < CustomParticleCount) ? self.customPathType : 0;
    return [NSString stringWithUTF8String:ParticleCustomDesc[index].desc];
}

-(int)numCustomPathParms {
    int index = (self.customPathType < CustomParticleCount ) ? self.customPathType : 0;
    return ParticleCustomDesc[index].count;
}

-(void)setCustomPathTypeFromName:(NSString *)p {
    self.customPathType = PPATH_STANDARD;
    for ( int i = 0; i < CustomParticleCount; i ++ ) {
        if (strcasecmp(p.UTF8String, ParticleCustomDesc[i].name) == 0) {
            self.customPathType = (prtCustomPth_t)(i);
            break;
        }
    }
}

-(void)copyFrom:(idParticleStage *)src {
    self.material = src.material;
    self.totalParticles = src.totalParticles;
    self.cycles = src.cycles;
    self.cycleMsec = src.cycleMsec;
    self.spawnBunching = src.spawnBunching;
    self.particleLife = src.particleLife;
    self.timeOffset = src.timeOffset;
    self.deadTime = src.deadTime;
    self.distributionType = src.distributionType;
    self.distributionParms = src.distributionParms;
    self.directionType = src.directionType;
    self.directionParms = src.directionParms;
    [self.speed copyFrom:src.speed];
    self.gravity = src.gravity;
    self.worldGravity = src.worldGravity;
    self.randomDistribution = src.randomDistribution;
    self.entityColor = src.entityColor;
    self.customPathType = src.customPathType;
    self.customPathParms = src.customPathParms;
    self.offset = src.offset;
    self.animationFrames = src.animationFrames;
    self.animationRate = src.animationRate;
    self.initialAngle = src.initialAngle;
    [self.rotationSpeed copyFrom:src.rotationSpeed];
    self.orientation = src.orientation;
    self.orientationParms = src.orientationParms;
    [self.size copyFrom:src.size];
    [self.aspect copyFrom:src.aspect];
    self.color = src.color;
    self.fadeColor = src.fadeColor;
    self.fadeInFraction = src.fadeInFraction;
    self.fadeOutFraction = src.fadeOutFraction;
    self.fadeIndexFraction = src.fadeIndexFraction;
    self.hidden = src.hidden;
    self.boundsExpansion = src.boundsExpansion;
    self.bounds = src.bounds;
}

@end

idDeclParticle *idDeclAllocator_idDeclParticle(void) {
    return [[idDeclParticle alloc] init];
}
