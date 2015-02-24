//
//  Demuxer.m
//  WD Content
//
//  Created by Sergey Seitov on 19.01.15.
//  Copyright (c) 2015 Sergey Seitov. All rights reserved.
//

#import "Demuxer.h"
#import "AudioStreamer.h"
#import "VTDecoder.h"

#include <mutex>
#include <queue>

extern "C" {
#	include "libavcodec/avcodec.h"
#	include "libavformat/avformat.h"
#	include "libavformat/avio.h"
#	include "libavfilter/avfilter.h"
};

enum {
    ThreadStillWorking,
    ThreadIsDone
};

@interface Demuxer () <VTDecoderDelegate> {
	
	dispatch_queue_t                _networkQueue;
    
    std::queue<CMSampleBufferRef>   _queue;
	std::mutex                      _mutex;
	int64_t                         _startPts;
}

@property (strong, nonatomic) VTDecoder *videoDecoder;
@property (strong, nonatomic) AudioStreamer *audioStreamer;

@property (atomic) int audioIndex;
@property (nonatomic) int videoIndex;

@property (atomic) AVFormatContext*	mediaContext;

@property (strong, nonatomic) NSCondition *demuxerState;
@property (strong, nonatomic) NSConditionLock *threadState;
@property (atomic) BOOL stopped;
@property (atomic) BOOL buffering;

@end

@implementation Demuxer

- (id)init
{
	self = [super init];
	if (self) {
		_audioStreamer = [[AudioStreamer alloc] init];
		_videoDecoder = [[VTDecoder alloc] init];
		_videoDecoder.delegate = self;
		
		_networkQueue = dispatch_queue_create("com.vchannel.WD-Content.SMBNetwork", DISPATCH_QUEUE_SERIAL);
        self.stopped = YES;
	}
	return self;
}

- (BOOL)loadMedia:(NSString*)url
{
	int err = avformat_open_input(&_mediaContext, [url UTF8String], NULL, NULL);
	if ( err != 0) {
		return NULL;
	}
	
	// Retrieve stream information
	avformat_find_stream_info(self.mediaContext, NULL);
	
	_audioIndex = -1;
	_videoIndex = -1;
	AVCodecContext* enc;
	
	for (unsigned i=0; i<self.mediaContext->nb_streams; ++i) {
		enc = self.mediaContext->streams[i]->codec;
		if (enc->codec_type == AVMEDIA_TYPE_AUDIO && enc->codec_descriptor) {
            if ([_audioStreamer openWithContext:enc]) {
                _audioIndex = i;
            }
		} else if (enc->codec_type == AVMEDIA_TYPE_VIDEO) {
			if ([_videoDecoder openWithContext:enc]) {
				_videoIndex = i;
			}
		}
	}

	return (_videoIndex >= 0 && _audioIndex >= 0);
}

- (void)open:(NSString*)path completion:(void (^)(BOOL))completion
{
	dispatch_async(_networkQueue, ^() {
        completion([self loadMedia:path]);
	});
}

- (void)play
{
	_threadState = [[NSConditionLock alloc] initWithCondition:ThreadStillWorking];
	_startPts = -1;
    self.stopped = NO;
	av_read_play(self.mediaContext);
	
	dispatch_async(_networkQueue, ^() {
		while (!self.stopped) {
			AVPacket nextPacket;
			if (av_read_frame(self.mediaContext, &nextPacket) < 0) { // eof
				break;
			}
			if (nextPacket.stream_index == self.audioIndex) {
				[_audioStreamer decodePacket:&nextPacket];
			} else if (nextPacket.stream_index == self.videoIndex) {
				if (_startPts < 0) {
					_startPts = nextPacket.pts;
				}
				nextPacket.pts -= _startPts;
				[_videoDecoder decodePacket:&nextPacket];
			}
            av_free_packet(&nextPacket);
		}
		[_threadState lock];
		[_threadState unlockWithCondition:ThreadIsDone];
	});
}

- (void)close
{
    if (self.stopped) return;
	self.stopped = YES;
	
	[_audioStreamer close];
	[_videoDecoder close];
	
	[_threadState lockWhenCondition:ThreadIsDone];
	[_threadState unlock];
	
    while (!_queue.empty()) {
        CMSampleBufferRef buffer = _queue.front();
        CFRelease(buffer);
        _queue.pop();
    }
    
	avformat_close_input(&_mediaContext);
}

#pragma mark - Video

- (void)decoder:(VTDecoder*)decoder decodedBuffer:(CMSampleBufferRef)buffer
{
    std::unique_lock<std::mutex> lock(_mutex);
    _queue.push(buffer);
}

- (CMSampleBufferRef)takeVideo
{
    std::unique_lock<std::mutex> lock(_mutex);
    if (_queue.empty()) {
        return NULL;
    }
    CMSampleBufferRef buffer = _queue.front();
    CMTime t = CMSampleBufferGetPresentationTimeStamp(buffer);
    if (t.value == AV_NOPTS_VALUE) {
        _queue.pop();
        return buffer;
    } else {
        double vt = t.value / 25.0;
        if (vt > _audioStreamer.currentTime) {
            buffer = NULL;
        } else {
            _queue.pop();
        }
        return buffer;
    }
}

@end
