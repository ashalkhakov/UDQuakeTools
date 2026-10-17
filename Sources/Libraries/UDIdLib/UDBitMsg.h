#import <Foundation/Foundation.h>

@interface UDBitMsg : NSObject

@property (nonatomic, strong, readonly) NSMutableData *data;

// Bit trackers
@property (nonatomic, assign) NSInteger readBit;
@property (nonatomic, assign) NSInteger writeBit;

// Byte trackers (Computed Properties)
@property (nonatomic, readonly) NSInteger readCount;  // Returns bytes read
@property (nonatomic, readonly) NSInteger writeCount; // Returns bytes written

// Initializers
- (instancetype)init;                                // For writing dynamically
- (instancetype)initWithData:(NSData *)existingData; // For reading from a network packet

-(int)size;

// Core API
- (void)writeBits:(uint32_t)value numBits:(int)numBits;
- (uint32_t)readBits:(int)numBits;

// idBitMsg's: a short with its sign (WriteBits( c, -16 )), an int, and a
// string, byte-aligned and ended by a 0 (GetByteSpace). ReadShort and
// ReadInt read -1 past the end; ReadString stops there, at a 0 or a 255,
// and reads '%' as '.' (as it guards the engine's printf-style routines).
- (void)writeByteAlign;
- (void)writeShort:(int)value;
- (void)writeInt:(int)value;
- (void)writeString:(NSString *)string;
- (void)readByteAlign;
- (int)readShort;
- (int)readInt;
- (NSString *)readString;

@end
