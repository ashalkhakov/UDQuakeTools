#import "UDParticlePreview.h"
#import "UDDeclManagedObjects.h"
#import "UDImageProgram.h"
#import "UDFXModel.h"
#import "UDParticleModel.h"
#import "UDSoftwareRenderer.h"
#import "UDWorkspace.h"

/// The timer's target: the preview, not held (the preview holds the timer).
@interface UDParticlePreviewTicker : NSObject
@property (nonatomic, weak) UDParticlePreview *preview;
- (void)tick:(NSTimer *)timer;
@end

@interface UDParticlePreview ()
@property (nonatomic, weak) NSImageView *imageView;
@property (nonatomic, weak) UDWorkspace *workspace;
@property (nonatomic, strong, nullable) UDParticleModel *model;
@property (nonatomic, strong, nullable) UDFXModel *fxModel;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, strong) NSDate *start;
@property (nonatomic, readwrite) int time;
@property (nonatomic, copy, readwrite) NSArray<UDFXActionState *> *fxStates;
@end

@implementation UDParticlePreviewTicker

- (void)tick:(NSTimer *)timer {
    UDParticlePreview *preview = self.preview;
    if (preview == nil) {
        [timer invalidate];
        return;
    }
    if (preview.imageView.window == nil) return;     // not shown
    [preview renderAtTime:(int)(-[preview.start timeIntervalSinceNow] * 1000)];
}

@end

@implementation UDParticlePreview

- (instancetype)initWithImageView:(NSImageView *)imageView workspace:(UDWorkspace *)workspace {
    self = [super init];
    if (self) {
        _imageView = imageView;
        _workspace = workspace;
        _start = [NSDate date];
        UDParticlePreviewTicker *ticker = [[UDParticlePreviewTicker alloc] init];
        ticker.preview = self;
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30 target:ticker selector:@selector(tick:) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)setStages:(NSArray<UDParticleStage *> *)stages {
    _stages = [stages copy];
    self.model = stages.count > 0 ? [[UDParticleModel alloc] initWithStages:stages declManager:self.workspace.declManager] : nil;
}

- (void)setFxActions:(NSArray<UDFXAction *> *)fxActions {
    _fxActions = [fxActions copy];
    self.fxModel = fxActions.count > 0 ? [[UDFXModel alloc] initWithActions:fxActions declManager:self.workspace.declManager] : nil;
}

- (int)fxDuration {
    return self.fxModel.duration;
}

- (void)restart {
    self.start = [NSDate date];
}

- (void)renderAtTime:(int)msec {
    UDFXModel *fxModel = self.fxModel;
    if (fxModel != nil) {
        // a "test" fx: activated again at its ClearFx, its Duration
        int period = MAX(fxModel.duration, 16) + 16;
        msec %= period;
        self.fxStates = [fxModel statesAtTime:msec];
    } else {
        self.fxStates = @[];
    }
    self.time = msec;
    NSImageView *imageView = self.imageView;
    UDParticleModel *model = self.model;
    int size = (int)MIN(MAX(MIN(NSWidth(imageView.bounds), NSHeight(imageView.bounds)), 32), 320);
    UDSoftwareRenderer *renderer = [[UDSoftwareRenderer alloc] initWithWidth:size height:size
                                                                 declManager:self.workspace.declManager
                                                                  fileSystem:self.workspace.fileSystem];
    const float background[4] = { 0.18f, 0.18f, 0.18f, 1 };
    [renderer clearToColor:background];
    if (model != nil || fxModel != nil) {
        // From the side, its bounds (GetStageBounds', which are generous)
        // filling the view: fov 90, as far back as they are wide.
        float bounds[6];
        if (fxModel != nil) [fxModel getBounds:bounds];
        else [model getBounds:bounds];
        float center[3] = { (bounds[0] + bounds[3]) / 2, (bounds[1] + bounds[4]) / 2, (bounds[2] + bounds[5]) / 2 };
        float radius = 0;
        for (int k = 0; k < 3; k++) radius = MAX(radius, (bounds[3 + k] - bounds[k]) / 2);
        const float axis[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
        float origin[3] = { center[0] - MAX(radius, 8) * 1.1f, center[1], center[2] };
        [renderer setViewOrigin:origin axis:axis fovX:90];
        NSArray<UDParticleSurface *> *surfaces = fxModel != nil ? [fxModel surfacesAtTime:msec viewAxis:axis]
                                                                 : [model surfacesAtTime:msec viewAxis:axis];
        [renderer drawSurfaces:surfaces time:msec * 0.001f];
    }
    UDImage *image = [renderer image];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:image.width pixelsHigh:image.height
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:image.width * 4
                                                                  bitsPerPixel:32];
    memcpy(rep.bitmapData, image.pixels.bytes, (size_t)(image.width * image.height * 4));
    NSImage *picture = [[NSImage alloc] initWithSize:NSMakeSize(image.width, image.height)];
    [picture addRepresentation:rep];
    imageView.image = picture;
    id target = self.target;
    if (target != nil && self.action != NULL) {
        [NSApp sendAction:self.action to:target from:self];
    }
}

@end
