//
//  VTDecoder.m
//  DirectVideo
//
//  Created by Sergey Seitov on 03.01.15.
//  Copyright (c) 2015 Sergey Seitov. All rights reserved.
//

#import "VTDecoder.h"
#import <VideoToolbox/VideoToolbox.h>

extern "C" {
#	include "VideoUtility.h"
}

static CMVideoFormatDescriptionRef CreateFormat(AVCodecContext* context, bool* convert)
{
	CMVideoFormatDescriptionRef format = NULL;
	OSStatus err = noErr;
    if (context->codec_id) {
        uint8_t* extradata = NULL;
        *convert = convertAvcc(context->extradata, context->extradata_size, &extradata);
        
        SpsHeader spsHeader = *((SpsHeader*)extradata);
        uint16_t spsLen = NTOHS(spsHeader.SPS_size);
        const uint8_t *sps = extradata+sizeof(SpsHeader);
        
        PpsHeader ppsHeader = *((PpsHeader*)(extradata + sizeof(SpsHeader)+spsLen));
        uint16_t ppsLen = NTOHS(ppsHeader.PPS_size);
        const uint8_t *pps = extradata+sizeof(SpsHeader)+spsLen+sizeof(PpsHeader);
        
        const uint8_t* const parameterSetPointers[2] = { sps , pps };
        const size_t parameterSetSizes[2] = { spsLen, ppsLen };
        
        err = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                  2,
                                                                  parameterSetPointers,
                                                                  parameterSetSizes,
                                                                  4,
                                                                  &format);
        if (err == noErr) {
            return format;
        }
    }
    return NULL;
}

void DeompressionDataCallbackHandler(void *decompressionOutputRefCon,
                                     void *sourceFrameRefCon,
                                     OSStatus status,
                                     VTDecodeInfoFlags infoFlags,
                                     CVImageBufferRef imageBuffer,
                                     CMTime presentationTimeStamp,
                                     CMTime presentationDuration );


@interface VTDecoder () {
	VTDecompressionSessionRef _session;
	CMVideoFormatDescriptionRef _videoFormat;
	bool convert_byte_stream;
}

@end

@implementation VTDecoder

- (BOOL)openWithContext:(AVCodecContext*)context
{
	convert_byte_stream = false;
	_videoFormat = CreateFormat(context, &convert_byte_stream);
	
	if (!_videoFormat) {
		return NO;
	}
	
	NSDictionary* destinationPixelBufferAttributes = @{
													   (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
													   (id)kCVPixelBufferWidthKey : [NSNumber numberWithInt:context->width],
													   (id)kCVPixelBufferHeightKey : [NSNumber numberWithInt:context->height],
													   (id)kCVPixelBufferOpenGLCompatibilityKey : [NSNumber numberWithBool:YES]
													   };

    VTDecompressionOutputCallbackRecord outputCallback;
    outputCallback.decompressionOutputCallback = DeompressionDataCallbackHandler;
    outputCallback.decompressionOutputRefCon = (__bridge void*)self;
	
    OSStatus status = VTDecompressionSessionCreate(NULL,
                                          _videoFormat,
                                          NULL,
												   (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                          &outputCallback,
                                          &_session);
    if (status == noErr) {
        VTSessionSetProperty(_session, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:4]);
        VTSessionSetProperty(_session, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
		self.context = context;
        return YES;
    } else {
        return NO;
    }
}

- (void)close
{
    if (_session) {
        VTDecompressionSessionInvalidate(_session);
        CFRelease(_session);
        _session = NULL;
    }
    if (_videoFormat) {
        CFRelease(_videoFormat);
        _videoFormat = NULL;
    }
}

- (void)decodePacket:(AVPacket*)packet
{
	double pts_scale = av_q2d(self.context->pkt_timebase) / (1.0/25.0);
	int64_t pts = (packet->pts == AV_NOPTS_VALUE) ? AV_NOPTS_VALUE : packet->pts*pts_scale;
	
	CMSampleTimingInfo timingInfo;
	timingInfo.presentationTimeStamp = CMTimeMake(pts, 1);
	timingInfo.duration = CMTimeMake(1, 1);
	timingInfo.decodeTimeStamp = kCMTimeInvalid;

	
	int demux_size = 0;
	uint8_t *demux_buff = NULL;
	if (convert_byte_stream) {
		// convert demuxer packet from bytestream (AnnexB) to bitstream
		AVIOContext *pb = NULL;
		if(avio_open_dyn_buf(&pb) < 0)
			return;
		demux_size = avc_parse_nal_units(pb, packet->data, packet->size);
		demux_size = avio_close_dyn_buf(pb, &demux_buff);

	} else {
		demux_buff = packet->data;
		demux_size = packet->size;
	}
	
	CMBlockBufferRef newBBufOut = NULL;
	OSStatus err = noErr;
	err = CMBlockBufferCreateWithMemoryBlock(
											 NULL,             // CFAllocatorRef structureAllocator
											 demux_buff,       // void *memoryBlock
											 demux_size,       // size_t blockLengt
											 kCFAllocatorNull, // CFAllocatorRef blockAllocator
											 NULL,             // const CMBlockBufferCustomBlockSource *customBlockSource
											 0,                // size_t offsetToData
											 demux_size,       // size_t dataLength
											 kCMBlockBufferAlwaysCopyDataFlag,            // CMBlockBufferFlags flags
											 &newBBufOut);     // CMBlockBufferRef *newBBufOut
	
	if (err != noErr) {
		NSLog(@"error CMBlockBufferCreateWithMemoryBlock");
		return;
	}
	
	CMSampleBufferRef sampleBuff = NULL;
	err = CMSampleBufferCreate(
							   kCFAllocatorDefault,		// CFAllocatorRef allocator
							   newBBufOut,				// CMBlockBufferRef dataBuffer
							   YES,						// Boolean dataReady
							   NULL,					// CMSampleBufferMakeDataReadyCallback makeDataReadyCallback
							   NULL,					// void *makeDataReadyRefcon
							   _videoFormat,			// CMFormatDescriptionRef formatDescription
							   1,						// CMItemCount numSamples
							   1,						// CMItemCount numSampleTimingEntries
							   &timingInfo,				// const CMSampleTimingInfo *sampleTimingArray
							   0,						// CMItemCount numSampleSizeEntries
							   NULL,					// const size_t *sampleSizeArray
							   &sampleBuff);			// CMSampleBufferRef *sBufOut
	if (err != noErr) {
		NSLog(@"error CMSampleBufferCreate");
		return;
	}
	CFRelease(newBBufOut);

	err = VTDecompressionSessionDecodeFrame(_session,
											sampleBuff,
											kVTDecodeFrame_EnableAsynchronousDecompression | kVTDecodeFrame_1xRealTimePlayback,
											sampleBuff,
											NULL);
    if (err != noErr) {
		NSLog(@"error VTDecompressionSessionDecodeFrame");
		CFRelease(sampleBuff);
    } else {
		VTDecompressionSessionWaitForAsynchronousFrames(_session);
    }
}

@end

void DeompressionDataCallbackHandler(void *decompressionOutputRefCon,
                                     void *sourceFrameRefCon,
                                     OSStatus status,
                                     VTDecodeInfoFlags infoFlags,
                                     CVImageBufferRef imageBuffer,
                                     CMTime presentationTimeStamp,
                                     CMTime presentationDuration )
{
	if (kVTDecodeInfo_FrameDropped & infoFlags) {
		NSLog(@"frame dropped");
		return;
	}
	
	VTDecoder* decoder = (__bridge VTDecoder*)decompressionOutputRefCon;
	CMSampleBufferRef decodeBuffer = (CMSampleBufferRef)sourceFrameRefCon;
	
    if (status == noErr) {
        CMVideoFormatDescriptionRef videoInfo = NULL;
        OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(NULL, imageBuffer, &videoInfo);
        if (status == noErr) {
            CMSampleBufferRef sampleBuffer = NULL;
			CMSampleTimingInfo timing;
			timing.presentationTimeStamp = presentationTimeStamp;
			timing.duration = presentationDuration;
			timing.decodeTimeStamp = presentationTimeStamp;
            status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                                        imageBuffer,
                                                        true,
                                                        NULL,
                                                        NULL,
                                                        videoInfo,
                                                        &timing,
                                                        &sampleBuffer);
            CFRelease(videoInfo);
            if (status == noErr) {
                [decoder.delegate decoder:decoder decodedBuffer:sampleBuffer];
			} else {
				NSLog(@"error CMSampleBufferCreateForImageBuffer");
			}
		} else {
			NSLog(@"error callback status");
		}
		CFRelease(decodeBuffer);
	} else {
		NSLog(@"decode error %d", (int)status);
	}
}
