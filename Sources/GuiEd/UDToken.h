#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, UDIdTokenKind) {
    UDIdTokenKindEOF = 0,
    UDIdTokenKindIdentifier,
    UDIdTokenKindString,
    UDIdTokenKindPunctuation,
};

@interface UDIdToken : NSObject

@property (nonatomic, assign) UDIdTokenKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) NSUInteger start;
@property (nonatomic, assign) NSUInteger end;

@end
