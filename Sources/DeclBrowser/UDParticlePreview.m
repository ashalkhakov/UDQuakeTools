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
@property (nonatomic, copy, readwrite, nullable) NSString *lightingProblem;
@end

@implementation UDParticlePreviewTicker

- (void)tick:(NSTimer *)timer {
    UDParticlePreview *preview = self.preview;
    if (preview == nil) {
        [timer invalidate];
        return;
    }
    if (preview.imageView.window == nil || !preview.playing) return;     // not shown, or paused
    int elapsed = (int)(-[preview.start timeIntervalSinceNow] * 1000);
    [preview renderAtTime:elapsed % MAX(preview.span, 1)];
}

@end

@implementation UDParticlePreview

- (instancetype)initWithImageView:(NSImageView *)imageView workspace:(UDWorkspace *)workspace {
    self = [super init];
    if (self) {
        _imageView = imageView;
        _workspace = workspace;
        _start = [NSDate date];
        _playing = YES;
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
    if (!self.playing) [self renderAtTime:self.time];
}

- (void)setFxActions:(NSArray<UDFXAction *> *)fxActions {
    _fxActions = [fxActions copy];
    self.fxModel = fxActions.count > 0 ? [[UDFXModel alloc] initWithActions:fxActions declManager:self.workspace.declManager] : nil;
    if (!self.playing) [self renderAtTime:self.time];
}

- (void)setMaterialText:(NSString *)materialText {
    _materialText = [materialText copy];
    if (!self.playing) [self renderAtTime:self.time];
}

- (int)span {
    if (self.materialName != nil) {
        return 10000;                       // a material runs on: ten seconds of it
    }
    if (self.fxModel != nil) {
        return MAX(self.fxModel.duration, 16) + 16;
    }
    // each stage: its offset, then its cycles of ( particleLife + deadTime ),
    // as idRenderModelPrt counts them
    float span = 0;
    for (UDParticleStage *stage in self.stages) {
        float cycles = stage.cycles > 0 ? stage.cycles : 2;
        span = MAX(span, stage.timeOffset + cycles * (stage.particleLife + stage.deadTime));
    }
    return MAX((int)(span * 1000), 100);
}

- (void)setPlaying:(BOOL)playing {
    if (playing && !_playing) {
        // on from where it was
        self.start = [NSDate dateWithTimeIntervalSinceNow:-self.time / 1000.0];
    }
    _playing = playing;
}

- (void)seekTo:(int)msec {
    self.playing = NO;
    [self renderAtTime:msec];
}

- (int)fxDuration {
    return self.fxModel.duration;
}

/// A square facing the view down +X at x @a x, @a size from its center out,
/// its texture once over it, its normal and tangents toward the view (as
/// R_DeriveTangents has a flat one's).
+ (UDParticleSurface *)squareWithMaterial:(NSString *)material at:(float)x size:(float)size shaderParms:(const float *)parms {
    const float center[3] = { 0, 0, 0 };
    return [self squareWithMaterial:material at:x size:size shaderParms:parms center:center];
}

+ (UDParticleSurface *)squareWithMaterial:(NSString *)material at:(float)x size:(float)size shaderParms:(const float *)parms
                                   center:(const float *)center {
    UDDrawVert quad[4];
    memset(quad, 0, sizeof(quad));
    const float ys[4] = { 1, -1, 1, -1 }, zs[4] = { 1, 1, -1, -1 }, ss[4] = { 0, 1, 0, 1 }, ts[4] = { 0, 0, 1, 1 };
    for (int k = 0; k < 4; k++) {
        quad[k].xyz[0] = x;
        quad[k].xyz[1] = center[1] + ys[k] * size;
        quad[k].xyz[2] = center[2] + zs[k] * size;
        quad[k].st[0] = ss[k];
        quad[k].st[1] = ts[k];
        quad[k].normal[0] = -1;             // toward the view
        quad[k].tangents[0][1] = -1;        // s grows to the view's right
        quad[k].tangents[1][2] = -1;        // t grows down
        quad[k].color[0] = quad[k].color[1] = quad[k].color[2] = quad[k].color[3] = 255;
    }
    return [UDParticleSurface surfaceWithMaterial:material verts:quad numVerts:4 shaderParms:parms];
}

- (void)restart {
    self.start = [NSDate date];
    if (!self.playing) [self renderAtTime:0];
}

- (void)renderAtTime:(int)msec {
    UDFXModel *fxModel = self.fxModel;
    if (fxModel != nil) {
        // a "test" fx: activated again at its ClearFx, its Duration
        msec %= self.span;
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
    const float axis[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
    float parms[12] = { 1, 1, 1, 1 };
    if (self.materialName != nil) {
        // The material on a 128 square at the origin, facing the view down
        // +X; a point light (lights/defaultPointLight, 300) before it, up and
        // to the left. The engine's order: the light's interactions, then
        // the ambient stages.
        if (self.materialText != nil) [renderer setMaterialText:self.materialText forName:self.materialName];
        float origin[3] = { -80, 0, 0 };
        [renderer setViewOrigin:origin axis:axis fovX:90];
        UDParticleSurface *square = [UDParticlePreview squareWithMaterial:self.materialName at:0 size:64 shaderParms:parms];
        UDPointLight *light = [[UDPointLight alloc] init];
        light.origin[0] = -60; light.origin[1] = 30; light.origin[2] = 30;
        [renderer drawInteractionsOfSurfaces:@[square] light:light time:msec * 0.001f];
        [renderer drawSurfaces:@[square] time:msec * 0.001f];
        self.lightingProblem = renderer.interactionProblem;
    } else if (model != nil || fxModel != nil) {
        // From the side, its bounds (GetStageBounds', which are generous)
        // filling the view: fov 90, as far back as they are wide.
        float bounds[6];
        if (fxModel != nil) [fxModel getBounds:bounds];
        else [model getBounds:bounds];
        float center[3] = { (bounds[0] + bounds[3]) / 2, (bounds[1] + bounds[4]) / 2, (bounds[2] + bounds[5]) / 2 };
        float radius = 0;
        for (int k = 0; k < 3; k++) radius = MAX(radius, (bounds[3 + k] - bounds[k]) / 2);
        radius = MAX(radius, 8);
        float origin[3] = { center[0] - radius * 1.1f, center[1], center[2] };
        [renderer setViewOrigin:origin axis:axis fovX:90];
        if (fxModel != nil) {
            // Its lights, on a wall behind it (no level here for them to
            // light): a plain diffuse surface, the engine's _white.
            NSArray<UDPointLight *> *lights = [fxModel lightsAtTime:msec];
            if (lights.count > 0) {
                [renderer setMaterialText:@"{ diffusemap _white }" forName:@"_preview/wall"];
                UDParticleSurface *wall = [UDParticlePreview squareWithMaterial:@"_preview/wall" at:center[0] + radius * 0.5f
                                                                           size:radius * 2 shaderParms:parms center:center];
                for (UDPointLight *light in lights) {
                    [renderer drawInteractionsOfSurfaces:@[wall] light:light time:msec * 0.001f];
                }
                self.lightingProblem = renderer.interactionProblem;
            }
        }
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
    [self.transport update];
    id target = self.target;
    if (target != nil && self.action != NULL) {
        [NSApp sendAction:self.action to:target from:self];
    }
}

@end
