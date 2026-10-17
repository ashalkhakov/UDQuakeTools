#import "UDBitMsg.h"

@implementation UDBitMsg

- (instancetype)init {
    self = [super init];
    if (self) {
        // Start with a small buffer, it will grow automatically
        _data = [[NSMutableData alloc] initWithCapacity:256];
        _readBit = 0;
        _writeBit = 0;
    }
    return self;
}

- (instancetype)initWithData:(NSMutableData *)existingData {
    self = [super init];
    if (self) {
        _data = existingData;
        _readBit = 0;
        _writeBit = 0;
    }
    return self;
}

-(int)size {
    return (int)_data.length;
}

- (NSInteger)readCount {
    // Calculates the number of bytes read (rounded up)
    return (_readBit + 7) >> 3;
}

- (NSInteger)writeCount {
    // Calculates the number of bytes written (rounded up)
    return (_writeBit + 7) >> 3;
}

// -----------------------------------------------------------------------------
// WRITING
// -----------------------------------------------------------------------------
- (void)writeBits:(uint32_t)value numBits:(int)numBits {
    if (numBits <= 0) return;
    if (numBits > 32) numBits = 32;
    
    // Mask off any garbage data above the requested bit count
    if (numBits != 32) {
        value &= ((1 << numBits) - 1);
    }
    
    // 1. Calculate required capacity
    NSInteger requiredBytes = (_writeBit + numBits + 7) >> 3;
    
    // 2. Automatically grow the buffer if needed!
    // Changing the length automatically zero-fills the new memory in Foundation.
    if (_data.length < requiredBytes) {
        _data.length = requiredBytes;
    }
    
    // 3. Get the raw C-pointer
    uint8_t *dest = (uint8_t *)_data.mutableBytes;
    
    // 4. The idTech bit-writing loop
    while (numBits > 0) {
        int byteOffset = (int)(_writeBit >> 3);
        int bitOffset  = (int)(_writeBit & 7);
        int bitsToWrite = 8 - bitOffset;
        
        if (bitsToWrite > numBits) {
            bitsToWrite = numBits;
        }
        
        int mask = (1 << bitsToWrite) - 1;
        int fraction = value & mask;
        
        // Clear the space, then OR the bits in
        dest[byteOffset] &= ~(mask << bitOffset);
        dest[byteOffset] |= (fraction << bitOffset);
        
        _writeBit += bitsToWrite;
        value >>= bitsToWrite;
        numBits -= bitsToWrite;
    }
}

// -----------------------------------------------------------------------------
// READING
// -----------------------------------------------------------------------------
- (uint32_t)readBits:(int)numBits {
    if (numBits <= 0) return 0;
    if (numBits > 32) numBits = 32;
    
    // Safety check: Don't read past the end of the buffer
    if (_readBit + numBits > _data.length * 8) {
        NSLog(@"UDBitMsg Error: Attempted to read past end of data buffer!");
        return 0;
    }
    
    const uint8_t *src = (const uint8_t *)_data.bytes;
    uint32_t value = 0;
    int valueBitOffset = 0;
    int bitsToRead = numBits;
    
    // The idTech bit-reading loop
    while (bitsToRead > 0) {
        int byteOffset = (int)(_readBit >> 3);
        int bitOffset  = (int)(_readBit & 7);
        int bitsAvailable = 8 - bitOffset;
        
        if (bitsAvailable > bitsToRead) {
            bitsAvailable = bitsToRead;
        }
        
        int mask = (1 << bitsAvailable) - 1;
        int fraction = (src[byteOffset] >> bitOffset) & mask;
        
        value |= (fraction << valueBitOffset);
        
        _readBit += bitsAvailable;
        valueBitOffset += bitsAvailable;
        bitsToRead -= bitsAvailable;
    }
    
    return value;
}

@end
