//
//  TVController.mm
//  Russia TV
//
//  Created by Sergey Seitov on 13.10.14.
//  Copyright (c) 2014 Sergey Seitov. All rights reserved.
//

#import "TVController.h"
#import "MBProgressHUD.h"
#import "Demuxer.h"

static NSString* mediaURL[4] = {
    @"http://panels.telemarker.cc/stream/ort-tm.ts",
    @"http://panels.telemarker.cc/stream/rtr-tm.ts",
    @"http://panels.telemarker.cc/stream/tvc-tm.ts",
    @"http://panels.telemarker.cc/stream/ntv-tm.ts"
};

@interface TVController () {
    dispatch_queue_t _videoOutputQueue;
}

@property (strong, nonatomic) Demuxer *demuxer;
@property (strong, nonatomic) AVSampleBufferDisplayLayer *videoOutput;
@property (strong, nonatomic) NSCondition *videoCondition;
@property (atomic) BOOL stopped;
@property (nonatomic) BOOL panelHidden;

@property (weak, nonatomic) IBOutlet UISegmentedControl *channels;
- (IBAction)setChannel:(UISegmentedControl *)sender;

@end

@implementation TVController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _videoOutputQueue = dispatch_queue_create("com.vchannel.WD-Content.VideoOutput", DISPATCH_QUEUE_SERIAL);
    
    _videoOutput = [[AVSampleBufferDisplayLayer alloc] init];
    _videoOutput.videoGravity = AVLayerVideoGravityResizeAspect;
    _videoOutput.backgroundColor = [[UIColor blackColor] CGColor];
    
    CMTimebaseRef tmBase = nil;
    CMTimebaseCreateWithMasterClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(),&tmBase);
    _videoOutput.controlTimebase = tmBase;
    CMTimebaseSetTime(_videoOutput.controlTimebase, kCMTimeZero);
    CMTimebaseSetRate(_videoOutput.controlTimebase, 25.0);

    _videoCondition = [[NSCondition alloc] init];
    
    _demuxer = [[Demuxer alloc] init];
    
    UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapOnScreen:)];
    [self.view addGestureRecognizer:tap];
    
    self.stopped = YES;
    
    _channels.selectedSegmentIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"Channel"];
    [self setChannel:_channels];
}

- (void)layoutScreen
{
    [_videoOutput removeFromSuperlayer];
    _videoOutput.bounds = self.view.bounds;
    _videoOutput.position = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    [self.view.layer addSublayer:_videoOutput];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self layoutScreen];
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [self layoutScreen];
}

- (void)tapOnScreen:(UITapGestureRecognizer *)tap
{
    _panelHidden = !_panelHidden;
    [self.navigationController setNavigationBarHidden:_panelHidden animated:YES];
    [self layoutScreen];
}

- (IBAction)setChannel:(UISegmentedControl *)sender
{
    [self stop];
    NSInteger channel = sender.selectedSegmentIndex;
    [[NSUserDefaults standardUserDefaults] setInteger:channel forKey:@"Channel"];
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    [_demuxer open:mediaURL[channel] completion:^(BOOL success) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^() {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        }];
        if (success) {
            [self play];
        } else {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^() {
                [self errorOpen];
            }];
        }
    }];
}

- (void)errorOpen
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                    message:@"Error open TV channel"
                                                   delegate:nil
                                          cancelButtonTitle:@"Ok"
                                          otherButtonTitles:nil];
    [alert show];
}


- (void)play
{
    [_demuxer play];
    
    self.stopped = NO;
    [_videoOutput requestMediaDataWhenReadyOnQueue:_videoOutputQueue usingBlock:^() {
        [_videoCondition lock];
        while (!self.stopped && _videoOutput.isReadyForMoreMediaData) {
            CMSampleBufferRef buffer = [_demuxer takeVideo];
            if (buffer) {
                [_videoOutput enqueueSampleBuffer:buffer];
                CFRelease(buffer);
            } else {
                break;
            }
        }
        [_videoCondition signal];
        [_videoCondition unlock];
    }];
}

- (void)stop
{
    if (self.stopped) return;
    
    [_videoCondition lock];
    self.stopped = YES;
    [_videoOutput stopRequestingMediaData];
    [_videoCondition wait];
    [_videoCondition unlock];
    [_videoOutput flushAndRemoveImage];
    [_demuxer close];
}

@end
