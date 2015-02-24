//
//  Renderer.h
//  vTV
//
//  Created by Sergey Seitov on 22.08.13.
//  Copyright (c) 2013 V-Channel. All rights reserved.
//

#import <GLKit/GLKit.h>
#import "Decoder.h"
#import "AudioOutput.h"
#import "VideoOutput.h"

struct AVPacket;

@interface Renderer : NSObject <GLKViewControllerDelegate>

@property (readwrite, nonatomic) int			videoIndex;
@property (readwrite, atomic) VideoOutput*		screen;

@property (readwrite, nonatomic) int			audioIndex;
@property (readwrite, atomic) AudioOutput*		audio;

- (void)setupScreenOnView:(UIView*)view;

- (id)init;
- (void)pushPacket:(AVPacket*)packet;
- (void)start;
- (void)stop;

@end
