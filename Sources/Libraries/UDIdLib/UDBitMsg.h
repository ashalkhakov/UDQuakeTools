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

@end
