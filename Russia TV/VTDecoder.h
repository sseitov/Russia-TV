//
//  VTDecoder.h
//  DirectVideo
//
//  Created by Sergey Seitov on 03.01.15.
//  Copyright (c) 2015 Sergey Seitov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

extern "C" {
#	include "libavcodec/avcodec.h"
}

@class VTDecoder;

@protocol VTDecoderDelegate <NSObject>

- (void)decoder:(VTDecoder*)decoder decodedBuffer:(CMSampleBufferRef)buffer;

@end

@interface VTDecoder : NSObject

- (BOOL)openWithContext:(AVCodecContext*)context;
- (void)close;
- (void)decodePacket:(AVPacket*)packet;

@property (atomic) AVCodecContext* context;
@property (weak, nonatomic) id<VTDecoderDelegate> delegate;

@end
