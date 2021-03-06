//
//  XDLive2DCaptureViewController.m
//  FaceXD
//
//  Created by CmST0us on 2020/4/4.
//  Copyright © 2020 hakura. All rights reserved.
//
#import <ARKit/ARKit.h>
#import <GLKit/GLKit.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <EKMetalKit/EKMetalKit.h>
#import <Masonry/Masonry.h>
#import <KVOController/KVOController.h>

#import "XDPackManager.h"
#import "LAppOpenGLContext.h"
#import "XDLive2DCaptureViewController.h"
#import "XDLive2DCaptureViewModel.h"
#import "XDLive2DCaptureARKitViewModel.h"
#import "XDLive2DCaptureDlibViewModel.h"

#import "LAppModel.h"

#import "XDDlibModelParameterConfiguration.h"
#import "XDDefaultModelParameterConfiguration.h"
#import "XDRawJSONNetworkPack.h"

@interface XDLive2DCaptureViewController () <GLKViewDelegate, XDLive2DCaptureViewModelDelegate> {
    CFTimeInterval _lastTime;
}
@property (nonatomic, strong) XDLive2DCaptureViewModel *viewModel;
@property (nonatomic, strong) LAppModel *live2DModel;
@property (nonatomic, strong) LAppOpenGLContext *glContext;

@property (nonatomic, strong) GLKView *glView;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) EKMetalRenderLiveview *liveviewRender;
@property (nonatomic, strong) MTKView *liveview;

@property (nonatomic, assign) CGSize modelSize;

@property (nonatomic, strong) XDDefaultModelParameterConfiguration *defaultModelParameterConfiguration;
@property (nonatomic, strong) XDDlibModelParameterConfiguration *dlibModelParameterConfiguration;
@end

@implementation XDLive2DCaptureViewController

- (instancetype)initWithModelName:(NSString *)modelName {
    self = [super init];
    if (self) {
        _glContext = [LAppOpenGLContext contextForObject:self];
        _viewModel = [[[self viewModelClass] alloc] init];
        _viewModel.delegate = self;
        [_glContext inContext:^{
            self.live2DModel = [[LAppModel alloc] initWithName:modelName glContext:self.glContext];
            [self.live2DModel loadAsset];
            [self.live2DModel startBreath];
        }];
    }
    return self;
}

- (void)bindData {
    __weak typeof(self) weakSelf = self;
    if ([self viewModelClass] == [XDLive2DCaptureARKitViewModel class]) {
        XDLive2DCaptureARKitViewModel *arViewModel = (XDLive2DCaptureARKitViewModel *)self.viewModel;
        [arViewModel addKVOObserver:self
                            forKeyPath:@"worldAlignment" block:^(id  _Nullable oldValue, id  _Nullable newValue) {
            weakSelf.defaultModelParameterConfiguration.worldAlignment = [newValue integerValue];
        }];
        self.defaultModelParameterConfiguration.worldAlignment = arViewModel.worldAlignment;
    }
    
    [self.viewModel addKVOObserver:self
                        forKeyPath:FBKVOKeyPath(_viewModel.advanceMode)
                             block:^(id  _Nullable oldValue, id  _Nullable newValue) {
        weakSelf.defaultModelParameterConfiguration.appendBlendShapes = [newValue boolValue];
    }];
    self.defaultModelParameterConfiguration.appendBlendShapes = self.viewModel.advanceMode;
}

- (void)viewDidLoad {
    self.glView = [[GLKView alloc] init];
    self.glView.delegate = self;
    self.glView.context = self.glContext.glContext;
    [self.view addSubview:self.glView];
    [self.glView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    
    EKMetalContext *context = [EKMetalContext defaultContext];
    self.liveview = [[MTKView alloc] initWithFrame:CGRectZero device:context.device];
    self.liveviewRender = [[EKMetalRenderLiveview alloc] initWithContext:context metalView:self.liveview];
    [self.liveviewRender setupRenderWithError:nil];
    [self.view addSubview:self.liveview];
    self.liveview.hidden = YES;
    [self layoutLiveview];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDispalyUpdate)];
    self.displayLink.preferredFramesPerSecond = 60;
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    self.defaultModelParameterConfiguration = [[XDDefaultModelParameterConfiguration alloc] initWithModel:self.live2DModel];
    self.dlibModelParameterConfiguration = [[XDDlibModelParameterConfiguration alloc] initWithModel:self.live2DModel];
    
    self.modelSize = self.view.bounds.size;
    [self bindData];
}

- (void)layoutLiveview {
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    [self.liveview mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.right.mas_equalTo(self.view).offset(-20);
        make.bottom.mas_equalTo(self.view).offset(-20);
        CGSize size = CGSizeMake(149, 254);
        if (orientation == UIInterfaceOrientationLandscapeLeft ||
            orientation == UIInterfaceOrientationLandscapeRight) {
            size = CGSizeMake(254, 149);
        }
        make.size.mas_equalTo(size);
    }];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    self.modelSize = size;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self layoutLiveview];
    });
}

- (void)resetModel {
    [self.defaultModelParameterConfiguration reset];
    [self.dlibModelParameterConfiguration reset];
}
#pragma mark - Handler
- (void)handleDispalyUpdate {
    [self.glView display];
}

#pragma mark - Data Source
- (Class)viewModelClass {
    if ([ARFaceTrackingConfiguration isSupported]) {
        return [XDLive2DCaptureARKitViewModel class];
    }
    return [XDLive2DCaptureDlibViewModel class];
}

#pragma mark - Delegate
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    [self.glContext updateTime];
    glClear(GL_COLOR_BUFFER_BIT);
    [self.live2DModel setMVPMatrixWithSize:self.modelSize];
    [self.live2DModel onUpdateWithParameterUpdate:^{
        if ([self viewModelClass] == [XDLive2DCaptureDlibViewModel class]) {
            [self.dlibModelParameterConfiguration commit];
        } else {
            [self.defaultModelParameterConfiguration commit];
        }
    }];
    glClearColor(0, 0, 0, 0);
}

- (void)viewModel:(XDLive2DCaptureViewModel *)viewModel didOutputFaceAnchor:(XDFaceAnchor *)faceAnchor {
    CFTimeInterval currentTime = CACurrentMediaTime();
    if (currentTime - _lastTime < 1.0 / 30.0) {
        return;
    }
    _lastTime = currentTime;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
        NSMutableDictionary *parm = [[NSMutableDictionary alloc] init];
        
        if ([self viewModelClass] == [XDLive2DCaptureDlibViewModel class]) {
            [self.dlibModelParameterConfiguration updateParameterWithFaceAnchor:faceAnchor];
            parm = [self.dlibModelParameterConfiguration.sendParameter parameterValueDictionary].mutableCopy;
        } else {
            self.defaultModelParameterConfiguration.orientation = orientation;
            [self.defaultModelParameterConfiguration updateParameterWithFaceAnchor:faceAnchor];

            parm = [self.defaultModelParameterConfiguration.sendParameter parameterValueDictionary].mutableCopy;
        }
        
        [self.viewModel.filterSendKeys enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString *removeKey = [[XDModelParameterConfiguration parameterKeyMap] objectForKey:obj];
            [parm removeObjectForKey:removeKey];
        }];
        
        XDRawJSONNetworkPack *pack = [[XDRawJSONNetworkPack alloc] initWithDictionary:parm];
        [[XDPackManager sharedInstance] sendPack:pack observer:self completion:nil];
    });
}

- (void)viewModel:(XDLive2DCaptureViewModel *)viewModel didOutputCameraPreview:(CMSampleBufferRef)sampleBuffer {
    CFRetain(sampleBuffer);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.liveview.hidden) {
            CFRelease(sampleBuffer);
            return;
        }
        UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
        EKMetalRenderLiveviewRotation rotation = EKMetalRenderLiveviewRotationRight;
        
        if ([self viewModelClass] == [XDLive2DCaptureDlibViewModel class]) {
            rotation = EKMetalRenderLiveviewRotationNormal;
        } else {
            if (orientation == UIInterfaceOrientationPortrait) {
                rotation = EKMetalRenderLiveviewRotationRight;
            } else if (orientation == UIInterfaceOrientationLandscapeRight) {
                rotation = EKMetalRenderLiveviewRotationNormal;
            } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
                rotation = EKMetalRenderLiveviewRotationUpsideDown;
            } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
                rotation = EKMetalRenderLiveviewRotationLeft;
            }
        }
        
        EKSampleBuffer *buffer = [[EKSampleBuffer alloc] initWithSampleBuffer:sampleBuffer freeWhenDone:YES];
        self.liveviewRender.orientation = rotation;
        [self.liveviewRender renderSampleBuffer:buffer];
    });

}
@end
