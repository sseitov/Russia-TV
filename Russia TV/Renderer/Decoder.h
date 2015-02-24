//
//  Decoder.h
//  vTV
//
//  Created by Sergey Seitov on 14.08.13.
//  Copyright (c) 2013 V-Channel. All rights reserved.
//

#import <Foundation/Foundation.h>

struct AVFrame;
struct AVPacket;
struct AVCodecContext;

@protocol Decoder <NSObject>

@property (readwrite, atomic) AVCodecContext* codec;
@property (readwrite, atomic) BOOL opened;

- (BOOL)openWithContext:(AVCodecContext*)codec;
- (void)close;
- (BOOL)decodePacket:(AVPacket*)packet toFrame:(AVFrame*)frame;

@end

@interface AudioDecoder : NSObject <Decoder>

@end

@interface VideoDecoder : NSObject <Decoder>


@end
