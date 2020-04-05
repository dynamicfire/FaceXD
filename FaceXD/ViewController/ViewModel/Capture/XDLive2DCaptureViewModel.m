//
//  XDLive2DCaptureViewModel.m
//  FaceXD
//
//  Created by CmST0us on 2020/4/4.
//  Copyright © 2020 hakura. All rights reserved.
//

#import "XDLive2DCaptureViewModel.h"
#import "XDUserDefineKeys.h"
@interface XDLive2DCaptureViewModel ()
@property (nonatomic, assign) BOOL isCapturing;
@end

@implementation XDLive2DCaptureViewModel

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
        _advanceMode = [userDefault boolForKey:XDUserDefineKeySubmitAdvancedSwitch];
    }
    return self;
}

- (void)startCapture {
    self.isCapturing = YES;
}

- (void)stopCapture {
    self.isCapturing = NO;
}

@end
