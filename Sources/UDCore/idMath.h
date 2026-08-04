//
//  idMath.h
//  PakManager
//
//  Created by artyom on 8/2/26.
//

typedef union idVec3_s {
    struct {
        float x;
        float y;
        float z;
    };
    float v[3];
} idVec3;

typedef union idVec4_s {
    struct {
        float x;
        float y;
        float z;
        float w;
    };
    float v[4];
} idVec4;

typedef union idBounds_s {
    struct {
        idVec3 mins;
        idVec3 maxs;
    };
    idVec3 b[2];   // b[0] = mins, b[1] = maxs
    float  v[6];   // Flat array of 6 floats
} idBounds;

typedef union idMat3_s {
    struct {
        idVec3 mat[3]; // 3 row vectors (each 12 bytes)
    };
    float mat3[3][3];  // 2D array [row][col]
    float v[9];        // Flat 9-element array
} idMat3;

typedef union idAngles_s {
    struct {
        float pitch; // x-axis rotation (up/down)
        float yaw;   // y-axis rotation (left/right)
        float roll;  // z-axis rotation (tilt)
    };
    float v[3];
} idAngles;

static inline idVec3 idVec3Make(float x, float y, float z) {
    idVec3 v;
    v.x = x;
    v.y = y;
    v.z = z;
    return v;
}

static inline idVec4 idVec4Make(float x, float y, float z, float w) {
    idVec4 v;
    v.x = x;
    v.y = y;
    v.z = z;
    v.w = w;
    return v;
}

static inline void idBoundsClear(idBounds *bounds) {
    bounds->mins.x = bounds->mins.y = bounds->mins.z =  9999999;
    bounds->maxs.x = bounds->maxs.y = bounds->maxs.z = -9999999;
}

static inline idBounds idBoundsZero(void) {
    idBounds b = {
        .mins = { .x = 0.0f, .y = 0.0f, .z = 0.0f },
        .maxs = { .x = 0.0f, .y = 0.0f, .z = 0.0f }
    };
    return b;
}

static inline idAngles idAnglesMake(float pitch, float yaw, float roll) {
    idAngles a;
    a.pitch = pitch;
    a.yaw   = yaw;
    a.roll  = roll;
    return a;
}

static inline idMat3 idMat3Identity(void) {
    idMat3 m = {
        .mat3 = {
            { 1.0f, 0.0f, 0.0f },
            { 0.0f, 1.0f, 0.0f },
            { 0.0f, 0.0f, 1.0f }
        }
    };
    return m;
}

static inline idMat3 idMat3FromRows(idVec3 row0, idVec3 row1, idVec3 row2) {
    idMat3 m;
    m.mat[0] = row0;
    m.mat[1] = row1;
    m.mat[2] = row2;
    return m;
}
