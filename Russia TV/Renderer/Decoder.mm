//
//  Decoder.m
//  vTV
//
//  Created by Sergey Seitov on 14.08.13.
//  Copyright (c) 2013 V-Channel. All rights reserved.
//

#import "Decoder.h"

extern "C" {
#	include "libavcodec/avcodec.h"
};

@implementation AudioDecoder

@synthesize codec, opened;

- (BOOL)openWithContext:(AVCodecContext*)context
{
	AVCodec* theCodec = avcodec_find_decoder(context->codec_id);
	if (!theCodec || avcodec_open2(context, theCodec, NULL) < 0)
		return NO;
	self.codec = context;
	return YES;
}

- (void)close
{
	if (self.codec) {
		avcodec_close(self.codec);
	}
	self.codec = 0;
}

- (BOOL)decodePacket:(AVPacket*)packet toFrame:(AVFrame*)frame
{
	int got_frame = 0;
	int len = -1;
	if (self.codec) {
		avcodec_get_frame_defaults(frame);
		len = avcodec_decode_audio4(self.codec, frame, &got_frame, packet);
	}
	if (len > 0 && got_frame) {
		frame->pts = frame->pkt_dts;
		if (frame->pts == AV_NOPTS_VALUE) {
			frame->pts = frame->pkt_pts;
		}
		return true;
	} else {
		return false;
	}
}

@end

@interface VideoDecoder ()

@end

@implementation VideoDecoder

@synthesize codec, opened;

- (BOOL)openWithContext:(AVCodecContext*)context
{
	AVCodec* theCodec = avcodec_find_decoder(context->codec_id);
	if (!theCodec || avcodec_open2(context, theCodec, NULL) < 0)
		return NO;

	self.codec = context;
	self.opened = YES;
	return YES;
}

- (void)close
{
	if (self.codec) {
		avcodec_close(self.codec);
	}
	self.opened = NO;
	self.codec = 0;
}

- (BOOL)decodePacket:(AVPacket*)packet toFrame:(AVFrame*)frame
{
	int got_frame = 0;
	int len = -1;
	if (self.codec) {
		avcodec_get_frame_defaults(frame);
		len = avcodec_decode_video2(self.codec, frame, &got_frame, packet);
	}
	if (len > 0 && got_frame) {
		frame->pts = frame->pkt_dts;
		if (frame->pts == AV_NOPTS_VALUE) {
			frame->pts = frame->pkt_pts;
		}
		return true;
	} else {
		return false;
	}
}

@end
