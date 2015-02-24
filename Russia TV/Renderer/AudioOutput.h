//
//  AudioOutput.h
//  vTV
//
//  Created by Sergey Seitov on 13.08.13.
//  Copyright (c) 2013 V-Channel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Decoder.h"

extern "C" {
#	include "libavcodec/avcodec.h"
#	include "libavformat/avformat.h"
};

#define AUDIO_POOL_SIZE 4

@interface AudioOutput : NSObject

@property (readonly, nonatomic) int64_t currentPTS;
@property (strong, nonatomic) id<Decoder> decoder;

- (void)currentPTS:(int64_t*)ppts withTime:(int64_t*)ptime;
- (void)stop;
- (void)reset;
- (void)flush:(int64_t)pts;
- (void)pushPacket:(AVPacket*)packet;
- (double)getCurrentTime;

- (int)decodedPacketCount;

@end
