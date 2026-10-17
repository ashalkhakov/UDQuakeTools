#import <AppKit/AppKit.h>

@class UDFXAction, UDFXActionState;

NS_ASSUME_NONNULL_BEGIN

/**
 * An FX's actions over its time: a lane each, its bar from its delay for its
 * duration (from random1 to random2 when it has them), lit while
 * idEntityFx::Run has it running; the time drawn, a line.
 */
@interface UDFXTimelineView : NSView
@property (nonatomic, copy, nullable) NSArray<UDFXAction *> *actions;
@property (nonatomic, copy, nullable) NSArray<UDFXActionState *> *states;
/// In milliseconds.
@property (nonatomic) int time;
@property (nonatomic) int duration;
/// A click or a drag along it: the time there (scrubTime) sent to its target.
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
@property (nonatomic, readonly) int scrubTime;
@end

NS_ASSUME_NONNULL_END
