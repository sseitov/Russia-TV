//
//  Renderer.m
//  vTV
//
//  Created by Sergey Seitov on 22.08.13.
//  Copyright (c) 2013 V-Channel. All rights reserved.
//

#import "Renderer.h"
#include "SynchroQueue.h"
#import "Util.h"

enum {
	DecoderStillWorking,
	DecoderIsFlashed
};

#define VIDEO_QUEUE_SIZE	SCREEN_POOL_SIZE*4
#define AUDIO_QUEUE_SIZE	AUDIO_POOL_SIZE*4

class PacketQueue : public SynchroQueue<AVPacket> {
	
	int freeToKeyWithPTS(int64_t pts)
	{
		int count = 0;
		std::list<AVPacket>::iterator it = _queue.begin();
		while (it != _queue.end()) {
			AVPacket pkt = *it;
			if (pkt.pts >= pts) {
				break;
			}
			if (pkt.flags != AV_PKT_FLAG_KEY) {
				av_free_packet(&pkt);
				it = _queue.erase(it);
				count++;
			} else {
				break;
			}
		}
		return count;
	}

	int _maxSize;
	
public:
	PacketQueue(int maxSize) : _maxSize(maxSize) {}
	
	virtual void free(AVPacket* packet)
	{
		av_free_packet(packet);
	}
		
	virtual bool push(AVPacket* packet)
	{
		std::unique_lock<std::mutex> lock(_mutex);
		if (_stopped) {
			return false;
		} else {
			_queue.push_back(*packet);
			if (_queue.size() > (_maxSize - 2)) {
				freeToKeyWithPTS(packet->pts);
			}
			_empty.notify_one();
			return true;
		}
	}

	virtual void flush(int64_t pts = AV_NOPTS_VALUE)
	{
		std::unique_lock<std::mutex> lock(_mutex);
		while (!_queue.empty()) {
			AVPacket pkt = _queue.front();
			if (pts == AV_NOPTS_VALUE || pkt.pts < pts) {
				free(&pkt);
				_queue.pop_front();
			} else
				break;
		}
		_empty.notify_one();
	}
};

@interface Renderer () {
	
	PacketQueue*	_videoQueue;
	PacketQueue*	_audioQueue;
}

@property (strong, nonatomic) NSConditionLock *audioDecoderState;
@property (strong, nonatomic) NSConditionLock *videoDecoderState;

@property (weak, nonatomic) UIView* parentView;

@property (readwrite, atomic) int64_t latestVideoPTS;

@end

@implementation Renderer

- (id)init
{
	self = [super init];
	if (self) {
		avcodec_register_all();
		
		_audio = [[AudioOutput alloc] init];
		_screen = [[VideoOutput alloc] initWithDelegate:self];
		
		_videoQueue = new PacketQueue(VIDEO_QUEUE_SIZE);
		_audioQueue = new PacketQueue(AUDIO_QUEUE_SIZE);
	}
	return self;
}

- (void)dealloc
{
	NSLog(@"[%@ dealloc]", self);
}

- (void)setupScreenOnView:(UIView*)view
{
	_parentView = view;
	_screen.glView.frame = view.bounds;
	_screen.glView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[view addSubview:_screen.glView];
	[view sendSubviewToBack:_screen.glView];
}

- (void)videoDecodeThread
{
	@autoreleasepool {
		[[NSThread currentThread] setThreadPriority:0.8];
		[[NSThread currentThread] setName:[NSString stringWithFormat:@"video-thread-Renderer:%@", self]];
		AVPacket packet;
		_videoDecoderState = [[NSConditionLock alloc] initWithCondition:DecoderStillWorking];
		while (_videoQueue->pop(&packet)) {
			[_screen pushPacket:&packet];
			av_free_packet(&packet);
		}
		[_videoDecoderState lock];
		[_videoDecoderState unlockWithCondition:DecoderIsFlashed];
	}
}

- (void)audioDecodeThread
{
	@autoreleasepool {
		[[NSThread currentThread] setThreadPriority:1.0];
		[[NSThread currentThread] setName:[NSString stringWithFormat:@"audio-thread-Renderer:%@", self]];
		AVPacket packet;
		_audioDecoderState = [[NSConditionLock alloc] initWithCondition:DecoderStillWorking];
		while (_audioQueue->pop(&packet)) {
			[_audio pushPacket:&packet];
			av_free_packet(&packet);
		}
		[_audioDecoderState lock];
		[_audioDecoderState unlockWithCondition:DecoderIsFlashed];
	}
}

- (void)start
{
	_audioQueue->start();
	[NSThread detachNewThreadSelector:@selector(audioDecodeThread) toTarget:self withObject:nil];
	
	_videoQueue->start();
	[NSThread detachNewThreadSelector:@selector(videoDecodeThread) toTarget:self withObject:nil];
}

- (void)stop
{
	////////////////////////////////
	// finish video
	
	_videoQueue->stop();
	[_screen flush:AV_NOPTS_VALUE];
	[_videoDecoderState lockWhenCondition:DecoderIsFlashed];
	[_videoDecoderState unlock];
	
	[_screen stop];
	_videoIndex = -1;
	
	////////////////////////////////
	// finish audio
	
	_audioQueue->stop();
	[_audio reset];
	[_audioDecoderState lockWhenCondition:DecoderIsFlashed];
	[_audioDecoderState unlock];
	
	[_audio stop];
	_audioIndex = -1;
	
	NSLog(@"RENDERER STOPPED");
}

- (void)pushPacket:(AVPacket*)packet
{
	if (packet->stream_index == _videoIndex) {
		if (!_videoQueue->push(packet)) {
			av_free_packet(packet);
		} else {
			self.latestVideoPTS = packet->pts;
		}
	} else if (packet->stream_index == _audioIndex) {
		if (!_audioQueue->push(packet)) {
			free(packet->data);
		}
	} else {
		av_free_packet(packet);
	}
}

#pragma mark - GLKViewController delegate methods

- (void)glkViewControllerUpdate:(GLKViewController *)controller
{
	int64_t currasp, currast;
	
	[_audio currentPTS:&currasp withTime:&currast];
	if (currasp == AV_NOPTS_VALUE)
		return;
	
	int64_t now = getUptimeInMilliseconds();
	int64_t xx = (now - currast) / 1000.0 * 90000.0;
	currasp = currasp + xx;
	//	NSLog(@"audio_tune=%lld", xx);
	
	int updated = 0;
	int64_t pts  = [_screen updateWithPTS:currasp updated:&updated];
	if (pts == AV_NOPTS_VALUE || updated == 0)
		return;
}

@end
