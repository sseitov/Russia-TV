//
//  TVController.mm
//  Russia TV
//
//  Created by Sergey Seitov on 13.10.14.
//  Copyright (c) 2014 Sergey Seitov. All rights reserved.
//

#import "TVController.h"
#import "MBProgressHUD.h"
#import "Renderer.h"

extern "C" {
#	include "libavcodec/avcodec.h"
#	include "libavformat/avformat.h"
#	include "libavformat/avio.h"
#	include "libavfilter/avfilter.h"
};

static NSString* mediaURL[6] = {
    @"http://panels.telemarker.cc/stream/ort-tm.ts",
    @"http://panels.telemarker.cc/stream/rtr-tm.ts",
    @"http://panels.telemarker.cc/stream/tvc-tm.ts",
    @"http://panels.telemarker.cc/stream/ntv-tm.ts",
    @"http://panels.telemarker.cc/stream/sts-tm.ts",
    @"http://panels.telemarker.cc/stream/tnt-tm.ts",
};

enum {
    ThreadStillWorking,
    ThreadIsDone
};

@interface TVController ()

@property (strong, nonatomic) IBOutlet UISegmentedControl *channels;

@property (strong, nonatomic) Renderer *renderer;

@property (readwrite, atomic) BOOL mediaRunning;
@property (strong, nonatomic) NSConditionLock *demuxerState;

@property (readwrite, atomic) AVFormatContext*	mediaContext;

@end

@implementation TVController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _channels = [[UISegmentedControl alloc] initWithItems:@[@"ОРТ",@"РТР",@"ТВЦ",@"НТВ",@"СТС",@"ТНТ"]];
    _channels.center = CGPointMake(self.view.center.x, 50);
    [_channels addTarget:self action:@selector(channelChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_channels];
    
    [self performSelector:@selector(hideChannels) withObject:nil afterDelay:1.0];
    
    UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(taspOnScreen:)];
    [[self view] addGestureRecognizer:tap];
    
    _renderer = [[Renderer alloc] init];
    [_renderer setupScreenOnView:self.view];
    
    _channels.selectedSegmentIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"Channel"];
    [self setChannel:(int)_channels.selectedSegmentIndex];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [UIView animateWithDuration:.3 animations:^(){
        CGRect frame = _channels.frame;
        frame.origin.x = (self.view.frame.size.width - frame.size.width)/2;
        _channels.frame = frame;
    }];
}

- (void)hideChannels
{
    [UIView animateWithDuration:.3 animations:^(){
        CGRect frame = _channels.frame;
        frame.origin.y = -49.0;
        frame.origin.x = (self.view.frame.size.width - frame.size.width)/2;
        _channels.frame = frame;
    }];
}

- (void)showChannels
{
    [UIView animateWithDuration:.3 animations:^(){
        CGRect frame = _channels.frame;
        frame.origin.y = 20;
        frame.origin.x = (self.view.frame.size.width - frame.size.width)/2;
        _channels.frame = frame;
    }];
}

- (void)taspOnScreen:(UITapGestureRecognizer*)gesture
{
    if (gesture.state == UIGestureRecognizerStateEnded) {
        if (_channels.frame.origin.y <= 0) {
            [self showChannels];
        } else {
            [self hideChannels];
        }
    }
}

- (IBAction)channelChanged:(UISegmentedControl *)sender
{
    [[NSUserDefaults standardUserDefaults] setInteger:sender.selectedSegmentIndex forKey:@"Channel"];
    [self setChannel:(int)sender.selectedSegmentIndex];
    [self hideChannels];
}

- (void)setChannel:(int)channel
{
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    [self closeMedia];
    [self performSelectorInBackground:@selector(openMedia:) withObject:mediaURL[channel]];
}
     
#pragma mark - Media demuxer

- (AVFormatContext*)loadMedia:(NSString*)url
{
    NSLog(@"open %@", url);
    AVFormatContext* mediaContext = 0;
    
    if (avformat_open_input(&mediaContext, [url UTF8String], NULL, NULL) < 0)
        return 0;
    
    // Retrieve stream information
    avformat_find_stream_info(mediaContext, NULL);
    
    AVCodecContext* enc;
    for (unsigned i=0; i<mediaContext->nb_streams; ++i) {
        enc = mediaContext->streams[i]->codec;
        if (enc->codec_type == AVMEDIA_TYPE_AUDIO) {
            if ([_renderer.audio.decoder openWithContext:enc]) {
                _renderer.audioIndex = i;
            } else {
                return 0;
            }
        } else if (enc->codec_type == AVMEDIA_TYPE_VIDEO) {
            if ([_renderer.screen.decoder openWithContext:enc]) {
                _renderer.videoIndex = i;
            } else {
                return 0;
            }
        }
    }
    
    return mediaContext;
}

- (void)errorOpen
{
    [MBProgressHUD hideHUDForView:self.view animated:YES];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                    message:@"Error open TV channel"
                                                   delegate:nil
                                          cancelButtonTitle:@"Ok"
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)openMedia:(NSString*)url
{
    @autoreleasepool {
        _mediaContext = [self loadMedia:url];
        if (!_mediaContext) {
            [self performSelectorOnMainThread:@selector(errorOpen) withObject:nil waitUntilDone:YES];
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^()
                       {
                           [MBProgressHUD hideHUDForView:self.view animated:YES];
                       });
        av_read_play(_mediaContext);
        
        _demuxerState = [[NSConditionLock alloc] initWithCondition:ThreadStillWorking];
        [_renderer start];
        _mediaRunning = YES;
        
        NSLog(@"media opened");
        while (_mediaRunning) {
            AVPacket nextPacket;
            // Read packet
            if (av_read_frame(_mediaContext, &nextPacket) < 0) { // eof
                av_free_packet(&nextPacket);
                break;
            }
            
            // Duplicate current packet
            if (av_dup_packet(&nextPacket) < 0) {	// error packet
                continue;
            }
            
            [_renderer pushPacket:&nextPacket];
        }
        
        avformat_close_input(&_mediaContext);
        _mediaContext = 0;
        [_demuxerState lock];
        [_demuxerState unlockWithCondition:ThreadIsDone];
    }
}

- (void)closeMedia
{
    if (_mediaRunning)
    {
        NSLog(@"======= Stop Renderer");
        [_renderer stop];
        NSLog(@"=======================================");
        _mediaRunning = NO;
        [_demuxerState lockWhenCondition:ThreadIsDone];
        [_demuxerState unlock];
    }
    else
    {
        return;
    }
    
    NSLog(@"media closed");
}

@end
