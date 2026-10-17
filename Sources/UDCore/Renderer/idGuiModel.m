/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idGuiModel.m — renderer/GuiModel.cpp, ported (its demo parts left out), and
 * what it clips with: idFixedWinding's ClipInPlace (geometry/Winding.cpp).
 */

#import "idGuiModel.h"
#import "idDeviceContext.h"

typedef struct {
    __unsafe_unretained idMaterial *material;
    float               color[4];
    int                 firstVert;
    int                 numVerts;
    int                 firstIndex;
    int                 numIndexes;
} guiModelSurface_t;

#pragma mark - idFixedWinding

#define MAX_POINTS_ON_WINDING   64
#define ON_EPSILON              0.1f
#define SIDE_FRONT              0
#define SIDE_BACK               1
#define SIDE_ON                 2

typedef struct { float x, y, z, s, t; } idVec5;

typedef struct {
    int     numPoints;
    idVec5  p[MAX_POINTS_ON_WINDING];
} idFixedWinding;

/// idPlane: its normal, and d (-dist).
typedef struct { float a, b, c, d; } idPlane;

static inline float idPlane_Distance( const idPlane *plane, const idVec5 *v ) {
    return plane->a * v->x + plane->b * v->y + plane->c * v->z + plane->d;
}

/*
=============
idWinding::ClipInPlace
=============
*/
static BOOL idWinding_ClipInPlace( idFixedWinding *w, const idPlane *plane, const float epsilon, const BOOL keepOn ) {
    float       dists[MAX_POINTS_ON_WINDING + 4];
    unsigned char sides[MAX_POINTS_ON_WINDING + 4];
    idVec5      newPoints[MAX_POINTS_ON_WINDING + 4];
    int         newNumPoints;
    int         counts[3];
    float       dot;
    int         i, j;
    idVec5 *    p1, *p2;
    idVec5      mid;
    int         maxpts;
    const float normal[3] = { plane->a, plane->b, plane->c };
    const float dist = -plane->d;

    counts[SIDE_FRONT] = counts[SIDE_BACK] = counts[SIDE_ON] = 0;

    // determine sides for each point
    for ( i = 0; i < w->numPoints; i++ ) {
        dists[i] = dot = idPlane_Distance( plane, &w->p[i] );
        if ( dot > epsilon ) {
            sides[i] = SIDE_FRONT;
        } else if ( dot < -epsilon ) {
            sides[i] = SIDE_BACK;
        } else {
            sides[i] = SIDE_ON;
        }
        counts[sides[i]]++;
    }
    sides[i] = sides[0];
    dists[i] = dists[0];

    // if the winding is on the plane and we should keep it
    if ( keepOn && !counts[SIDE_FRONT] && !counts[SIDE_BACK] ) {
        return YES;
    }
    // if nothing at the front of the clipping plane
    if ( !counts[SIDE_FRONT] ) {
        w->numPoints = 0;
        return NO;
    }
    // if nothing at the back of the clipping plane
    if ( !counts[SIDE_BACK] ) {
        return YES;
    }

    maxpts = w->numPoints + 4;      // cant use counts[0]+2 because of fp grouping errors

    newNumPoints = 0;

    for ( i = 0; i < w->numPoints; i++ ) {
        p1 = &w->p[i];

        if ( newNumPoints+1 > maxpts ) {
            return YES;        // can't split -- fall back to original
        }

        if ( sides[i] == SIDE_ON ) {
            newPoints[newNumPoints] = *p1;
            newNumPoints++;
            continue;
        }

        if ( sides[i] == SIDE_FRONT ) {
            newPoints[newNumPoints] = *p1;
            newNumPoints++;
        }

        if ( sides[i+1] == SIDE_ON || sides[i+1] == sides[i] ) {
            continue;
        }

        if ( newNumPoints+1 > maxpts ) {
            return YES;        // can't split -- fall back to original
        }

        // generate a split point
        p2 = &w->p[(i+1)%w->numPoints];

        dot = dists[i] / (dists[i] - dists[i+1]);
        float *m = &mid.x;
        const float *a = &p1->x, *b = &p2->x;
        for ( j = 0; j < 3; j++ ) {
            // avoid round off error when possible
            if ( normal[j] == 1.0f ) {
                m[j] = dist;
            } else if ( normal[j] == -1.0f ) {
                m[j] = -dist;
            } else {
                m[j] = a[j] + dot * ( b[j] - a[j] );
            }
        }
        mid.s = p1->s + dot * ( p2->s - p1->s );
        mid.t = p1->t + dot * ( p2->t - p1->t );

        newPoints[newNumPoints] = mid;
        newNumPoints++;
    }

    if ( newNumPoints > MAX_POINTS_ON_WINDING ) {
        return YES;
    }

    w->numPoints = newNumPoints;
    memcpy( w->p, newPoints, newNumPoints * sizeof(idVec5) );

    return YES;
}

#pragma mark - idGuiModel

@implementation idGuiModel {
    idMaterial *defaultMaterial;
    guiModelSurface_t *surfaces;
    int numSurfaces, maxSurfaces;
    int surf;                       // the current surface's index
    NSMutableData *verts;           // UDDrawVert
    NSMutableData *indexes;         // int
}

- (instancetype)initWithDefaultMaterial:(idMaterial *)material {
    self = [super init];
    if (self) {
        defaultMaterial = material;
        verts = [NSMutableData data];
        indexes = [NSMutableData data];
        [self clear];
    }
    return self;
}

- (void)dealloc {
    free( surfaces );
}

- (int)numVerts { return (int)( verts.length / sizeof( UDDrawVert ) ); }
- (int)numIndexes { return (int)( indexes.length / sizeof( int ) ); }

/*
================
idGuiModel::Clear

Begins collecting draw commands into surfaces
================
*/
- (void)clear {
    numSurfaces = 0;
    verts.length = 0;
    indexes.length = 0;
    [self advanceSurf];
}

/*
=============
AdvanceSurf
=============
*/
- (void)advanceSurf {
    guiModelSurface_t s;

    if ( numSurfaces ) {
        s.color[0] = surfaces[surf].color[0];
        s.color[1] = surfaces[surf].color[1];
        s.color[2] = surfaces[surf].color[2];
        s.color[3] = surfaces[surf].color[3];
        s.material = surfaces[surf].material;
    } else {
        s.color[0] = 1;
        s.color[1] = 1;
        s.color[2] = 1;
        s.color[3] = 1;
        s.material = defaultMaterial;
    }
    s.numIndexes = 0;
    s.firstIndex = [self numIndexes];
    s.numVerts = 0;
    s.firstVert = [self numVerts];

    if ( numSurfaces == maxSurfaces ) {
        maxSurfaces = maxSurfaces ? maxSurfaces * 2 : 64;
        surfaces = realloc( surfaces, sizeof( guiModelSurface_t ) * maxSurfaces );
    }
    surfaces[numSurfaces++] = s;
    surf = numSurfaces - 1;
}

/*
=============
SetColor
=============
*/
- (void)setColor:(float)r g:(float)g b:(float)b a:(float)a {
    guiModelSurface_t *s = &surfaces[surf];
    if ( r == s->color[0] && g == s->color[1]
        && b == s->color[2] && a == s->color[3] ) {
        return; // no change
    }

    if ( s->numVerts ) {
        [self advanceSurf];
        s = &surfaces[surf];
    }

    // change the parms
    s->color[0] = r;
    s->color[1] = g;
    s->color[2] = b;
    s->color[3] = a;
}

/*
=============
DrawStretchPic
=============
*/
- (void)drawStretchPic:(const UDDrawVert *)dverts indexes:(const int *)dindexes vertCount:(int)vertCount indexCount:(int)indexCount
              material:(idMaterial *)hShader clip:(BOOL)clip minX:(float)min_x minY:(float)min_y maxX:(float)max_x maxY:(float)max_y {
    if ( !( dverts && dindexes && vertCount && indexCount && hShader ) ) {
        return;
    }

    // break the current surface if we are changing to a new material
    if ( hShader != surfaces[surf].material ) {
        if ( surfaces[surf].numVerts ) {
            [self advanceSurf];
        }
        surfaces[surf].material = hShader;
    }

    // add the verts and indexes to the current surface

    if ( clip ) {
        int i, j;

        // FIXME:   this is grim stuff, and should be rewritten if we have any significant
        //          number of guis asking for clipping
        idFixedWinding w;
        for ( i = 0; i < indexCount; i += 3 ) {
            w.numPoints = 0;
            for ( int k = 0; k < 3; k++ ) {
                const UDDrawVert *v = &dverts[dindexes[i+k]];
                idVec5 p = { v->xyz[0], v->xyz[1], v->xyz[2], v->st[0], v->st[1] };
                w.p[w.numPoints++] = p;
            }

            for ( j = 0; j < 3; j++ ) {
                if ( w.p[j].x < min_x || w.p[j].x > max_x ||
                    w.p[j].y < min_y || w.p[j].y > max_y ) {
                    break;
                }
            }
            if ( j < 3 ) {
                idPlane p;
                p.b = p.c = 0.0f; p.a = 1.0f; p.d = -min_x;
                idWinding_ClipInPlace( &w, &p, ON_EPSILON, NO );
                p.b = p.c = 0.0f; p.a = -1.0f; p.d = max_x;
                idWinding_ClipInPlace( &w, &p, ON_EPSILON, NO );
                p.a = p.c = 0.0f; p.b = 1.0f; p.d = -min_y;
                idWinding_ClipInPlace( &w, &p, ON_EPSILON, NO );
                p.a = p.c = 0.0f; p.b = -1.0f; p.d = max_y;
                idWinding_ClipInPlace( &w, &p, ON_EPSILON, NO );
            }

            int numVerts = [self numVerts];
            verts.length += w.numPoints * sizeof( UDDrawVert );
            UDDrawVert *vs = (UDDrawVert *)verts.mutableBytes;
            for ( j = 0 ; j < w.numPoints ; j++ ) {
                UDDrawVert *dv = &vs[numVerts+j];

                memset( dv, 0, sizeof( *dv ) );
                dv->xyz[0] = w.p[j].x;
                dv->xyz[1] = w.p[j].y;
                dv->xyz[2] = w.p[j].z;
                dv->st[0] = w.p[j].s;
                dv->st[1] = w.p[j].t;
                dv->normal[0] = 0; dv->normal[1] = 0; dv->normal[2] = 1;
                dv->tangents[0][0] = 1; dv->tangents[0][1] = 0; dv->tangents[0][2] = 0;
                dv->tangents[1][0] = 0; dv->tangents[1][1] = 1; dv->tangents[1][2] = 0;
            }
            surfaces[surf].numVerts += w.numPoints;

            for ( j = 2; j < w.numPoints; j++ ) {
                int tri[3] = {
                    numVerts - surfaces[surf].firstVert,
                    numVerts + j - 1 - surfaces[surf].firstVert,
                    numVerts + j - surfaces[surf].firstVert
                };
                [indexes appendBytes:tri length:sizeof( tri )];
                surfaces[surf].numIndexes += 3;
            }
        }

    } else {

        int numVerts = [self numVerts];

        surfaces[surf].numVerts += vertCount;
        surfaces[surf].numIndexes += indexCount;

        for ( int i = 0; i < indexCount; i++ ) {
            int index = numVerts + dindexes[i] - surfaces[surf].firstVert;
            [indexes appendBytes:&index length:sizeof( index )];
        }

        [verts appendBytes:dverts length:vertCount * sizeof( UDDrawVert )];
    }
}

static void SetGuiVert( UDDrawVert *v, float x, float y, float s, float t ) {
    // idDrawVert has no constructor; its color is whatever was there (here 0)
    memset( v, 0, sizeof( *v ) );
    v->xyz[0] = x;
    v->xyz[1] = y;
    v->xyz[2] = 0;
    v->st[0] = s;
    v->st[1] = t;
    v->normal[0] = 0;
    v->normal[1] = 0;
    v->normal[2] = 1;
    v->tangents[0][0] = 1;
    v->tangents[0][1] = 0;
    v->tangents[0][2] = 0;
    v->tangents[1][0] = 0;
    v->tangents[1][1] = 1;
    v->tangents[1][2] = 0;
}

/*
=============
DrawStretchPic

x/y/w/h are in the 0,0 to 640,480 range
=============
*/
- (void)drawStretchPic:(float)x y:(float)y w:(float)w h:(float)h s1:(float)s1 t1:(float)t1 s2:(float)s2 t2:(float)t2 material:(idMaterial *)hShader {
    UDDrawVert dverts[4];
    int dindexes[6];

    if ( !hShader ) {
        return;
    }

    // clip to edges, because the pic may be going into a guiShader
    // instead of full screen
    if ( x < 0 ) {
        s1 += ( s2 - s1 ) * -x / w;
        w += x;
        x = 0;
    }
    if ( y < 0 ) {
        t1 += ( t2 - t1 ) * -y / h;
        h += y;
        y = 0;
    }
    if ( x + w > 640 ) {
        s2 -= ( s2 - s1 ) * ( x + w - 640 ) / w;
        w = 640 - x;
    }
    if ( y + h > 480 ) {
        t2 -= ( t2 - t1 ) * ( y + h - 480 ) / h;
        h = 480 - y;
    }

    if ( w <= 0 || h <= 0 ) {
        return;     // completely clipped away
    }

    dindexes[0] = 3;
    dindexes[1] = 0;
    dindexes[2] = 2;
    dindexes[3] = 2;
    dindexes[4] = 0;
    dindexes[5] = 1;
    SetGuiVert( &dverts[0], x, y, s1, t1 );
    SetGuiVert( &dverts[1], x + w, y, s2, t1 );
    SetGuiVert( &dverts[2], x + w, y + h, s2, t2 );
    SetGuiVert( &dverts[3], x, y + h, s1, t2 );

    [self drawStretchPic:dverts indexes:dindexes vertCount:4 indexCount:6 material:hShader clip:NO minX:0.0f minY:0.0f maxX:640.0f maxY:480.0f];
}

/*
=============
DrawStretchTri

x/y/w/h are in the 0,0 to 640,480 range
=============
*/
- (void)drawStretchTri:(idVec2)p1 p2:(idVec2)p2 p3:(idVec2)p3 t1:(idVec2)t1 t2:(idVec2)t2 t3:(idVec2)t3 material:(idMaterial *)material {
    UDDrawVert tempVerts[3];
    int tempIndexes[3];
    int vertCount = 3;
    int indexCount = 3;

    if ( !material ) {
        return;
    }

    tempIndexes[0] = 1;
    tempIndexes[1] = 0;
    tempIndexes[2] = 2;
    SetGuiVert( &tempVerts[0], p1.x, p1.y, t1.x, t1.y );
    SetGuiVert( &tempVerts[1], p2.x, p2.y, t2.x, t2.y );
    SetGuiVert( &tempVerts[2], p3.x, p3.y, t3.x, t3.y );

    // break the current surface if we are changing to a new material
    if ( material != surfaces[surf].material ) {
        if ( surfaces[surf].numVerts ) {
            [self advanceSurf];
        }
        surfaces[surf].material = material;
    }

    int numVerts = [self numVerts];

    surfaces[surf].numVerts += vertCount;
    surfaces[surf].numIndexes += indexCount;

    for ( int i = 0; i < indexCount; i++ ) {
        int index = numVerts + tempIndexes[i] - surfaces[surf].firstVert;
        [indexes appendBytes:&index length:sizeof( index )];
    }

    [verts appendBytes:tempVerts length:vertCount * sizeof( UDDrawVert )];
}

/*
================
idGuiModel::EmitFullScreen

Creates a view that covers the screen and emit the surfaces
================
*/
- (NSArray<UDParticleSurface *> *)emitFullScreen {
    NSMutableArray<UDParticleSurface *> *drawSurfs = [NSMutableArray array];

    if ( surfaces[0].numVerts == 0 ) {
        return drawSurfs;
    }

    const UDDrawVert *allVerts = verts.bytes;
    const int *allIndexes = indexes.bytes;
    for ( int i = 0 ; i < numSurfaces ; i++ ) {
        guiModelSurface_t *s = &surfaces[i];
        // EmitSurface
        if ( s->numVerts == 0 ) {
            continue;       // nothing in the surface
        }
        float shaderParms[12] = { 0 };
        memcpy( shaderParms, s->color, sizeof( s->color ) );
        [drawSurfs addObject:[UDParticleSurface surfaceWithMaterial:s->material.name
                                                              verts:allVerts + s->firstVert numVerts:s->numVerts
                                                            indexes:allIndexes + s->firstIndex numIndexes:s->numIndexes
                                                        shaderParms:shaderParms]];
    }
    return drawSurfs;
}

@end
