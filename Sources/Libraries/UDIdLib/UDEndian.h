#import <Foundation/Foundation.h>
#import <Foundation/NSByteOrder.h>

// -----------------------------------------------------------------------------
// 16-Bit Integers
// -----------------------------------------------------------------------------
static inline int16_t LittleShort(int16_t l) {
    return (int16_t)NSSwapLittleShortToHost((uint16_t)l);
}

static inline int16_t BigShort(int16_t l) {
    return (int16_t)NSSwapBigShortToHost((uint16_t)l);
}

// -----------------------------------------------------------------------------
// 32-Bit Integers (The 64-bit 'long' fix)
// -----------------------------------------------------------------------------
// We force int32_t and use NSSwapLittleIntToHost.
// Do NOT use NSSwapLittleLongToHost on 64-bit systems!

static inline int32_t LittleLong(int32_t l) {
    return (int32_t)NSSwapLittleIntToHost((uint32_t)l);
}

static inline int32_t BigLong(int32_t l) {
    return (int32_t)NSSwapBigIntToHost((uint32_t)l);
}

// -----------------------------------------------------------------------------
// 32-Bit Floats
// -----------------------------------------------------------------------------
// Foundation's float swapping expects an NSSwappedFloat struct, which requires
// annoying conversions. idTech uses a union trick to alias the memory safely,
// which is much faster and avoids strict-aliasing compiler warnings.

static inline float LittleFloat(float l) {
    union { float f; uint32_t i; } u;
    u.f = l;
    u.i = (uint32_t)NSSwapLittleIntToHost(u.i);
    return u.f;
}

static inline float BigFloat(float l) {
    union { float f; uint32_t i; } u;
    u.f = l;
    u.i = (uint32_t)NSSwapBigIntToHost(u.i);
    return u.f;
}

// -----------------------------------------------------------------------------
// In-Place Array Byte Reversal
// -----------------------------------------------------------------------------

// Helper function that unconditionally swaps bytes using hardware CPU intrinsics
static inline void UDSystemRevBytes(void *bp, int elsize, int elcount) {
    // Ordered by statistical probability in idTech (4-byte floats/ints are most common)
    if (elsize == 4) {
        uint32_t *p = (uint32_t *)bp;
        for (int i = 0; i < elcount; i++) {
            p[i] = NSSwapInt(p[i]);
        }
    }
    else if (elsize == 2) {
        uint16_t *p = (uint16_t *)bp;
        for (int i = 0; i < elcount; i++) {
            p[i] = NSSwapShort(p[i]);
        }
    }
    else if (elsize == 8) {
        uint64_t *p = (uint64_t *)bp;
        for (int i = 0; i < elcount; i++) {
            p[i] = NSSwapLongLong(p[i]);
        }
    }
}

// Reverses bytes ONLY if the host CPU is Big-Endian
static inline void LittleRevBytes(void *bp, int elsize, int elcount) {
    if (NSHostByteOrder() == NS_BigEndian) {
        UDSystemRevBytes(bp, elsize, elcount);
    }
}

// Reverses bytes ONLY if the host CPU is Little-Endian
static inline void BigRevBytes(void *bp, int elsize, int elcount) {
    if (NSHostByteOrder() == NS_LittleEndian) {
        UDSystemRevBytes(bp, elsize, elcount);
    }
}
