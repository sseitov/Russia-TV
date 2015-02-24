//
//  AudioOutput.m
//  vTV
//
//  Created by Sergey Seitov on 13.08.13.
//  Copyright (c) 2013 V-Channel. All rights reserved.
//

#import "AudioOutput.h"
#include <AudioToolbox/AudioToolbox.h>
#include "AudioRingBuffer.h"

static std::mutex audioMutex;

@interface AudioOutput () {
	
	AudioStreamBasicDescription			_dataFormat;
	AudioQueueRef						_queue;
    AudioQueueTimelineRef				_timeLine;
	AudioRingBuffer*					_ringBuffer;
	AudioQueueBufferRef					_pool[AUDIO_POOL_SIZE];
}

@property (readwrite, nonatomic) BOOL started;

@end

static void AudioOutputCallback(void *inClientData,
								AudioQueueRef inAQ,
								AudioQueueBufferRef inBuffer)
{
	AudioRingBuffer *rb = (AudioRingBuffer*)inClientData;
	if (!readRingBuffer(rb, inBuffer)) {
		memset(inBuffer->mAudioData, 0, rb->_bufferSize);
		inBuffer->mAudioDataByteSize = rb->_bufferSize;
	}

	AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
}

@implementation AudioOutput

- (id)init
{
	self = [super init];
	if (self) {
		self.decoder = [[AudioDecoder alloc] init];
	}
	return self;
}

- (void)currentPTS:(int64_t*)ppts withTime:(int64_t*)ptime
{
	if (_ringBuffer != NULL)
		ringBufferPTSWithTime(_ringBuffer, ppts, ptime);
	else {
		*ppts = AV_NOPTS_VALUE;
		*ptime = AV_NOPTS_VALUE;
	}
}

- (int64_t)currentPTS
{
	return (_ringBuffer ? ringBufferPTS(_ringBuffer) : AV_NOPTS_VALUE);
}

- (BOOL)startWithFrame:(AVFrame*)frame
{
	if (_started) return NO;
	
	_dataFormat.mFormatID = kAudioFormatLinearPCM;
	_dataFormat.mSampleRate = frame->sample_rate;
	_dataFormat.mBitsPerChannel = av_get_bytes_per_sample((AVSampleFormat)frame->format)*8;
	
	if (frame->channels > 2) {
		_dataFormat.mChannelsPerFrame = 2;
	} else {
		_dataFormat.mChannelsPerFrame = frame->channels;
	}
	
	if (frame->format == AV_SAMPLE_FMT_FLTP) {//
		_dataFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	} else if (frame->format == AV_SAMPLE_FMT_S16) {
		_dataFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	} else {
		NSLog(@"UNKNOWN SAMPLE FORMAT %d", frame->format);
		return NO;
	}
	_dataFormat.mBytesPerPacket = _dataFormat.mBytesPerFrame = (_dataFormat.mBitsPerChannel / 8) * _dataFormat.mChannelsPerFrame;
	_dataFormat.mFramesPerPacket = 1;
	
	int bufferSize;
	if (frame->channels == 1 || frame->format == AV_SAMPLE_FMT_S16) {
		bufferSize = av_samples_get_buffer_size(NULL, _dataFormat.mChannelsPerFrame, frame->nb_samples, (AVSampleFormat)frame->format, 1);
	} else {
		bufferSize = frame->nb_samples*sizeof(StereoFloatSample);
	}
	
	_ringBuffer = new AudioRingBuffer(AUDIO_POOL_SIZE, bufferSize);
		
	AudioQueueNewOutput(&_dataFormat, AudioOutputCallback, _ringBuffer, NULL, 0, 0, &_queue);
	AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, 1.0);
	AudioQueueCreateTimeline(_queue, &_timeLine);
	
	for (int i=0; i<AUDIO_POOL_SIZE; i++) {
		AudioQueueAllocateBuffer(_queue, bufferSize, &_pool[i]);
		_pool[i]->mAudioDataByteSize = bufferSize;
		memset(_pool[i]->mAudioData, 0, bufferSize);
		AudioQueueEnqueueBuffer(_queue, _pool[i], 0, NULL);
	}
	OSStatus startResult = AudioQueueStart(_queue, 0);
	self.started = YES;
	if (startResult != 0) {
		NSLog(@"Audio not started, stopping");
		[self stop];
		return NO;
	} else {
		NSLog(@"Audio started");
		return YES;
	}
}

- (void)reset
{
	if (_ringBuffer) {
		resetRingBuffer(_ringBuffer);
	}
}

- (void)flush:(int64_t)pts
{
	if (_ringBuffer) {
		flushRingBuffer(_ringBuffer);
	}
}

- (void)stop
{
	if (!_started) return;
	
	AudioQueueStop(_queue, true);
	for (int i=0; i<AUDIO_POOL_SIZE; i++) {
		AudioQueueFreeBuffer(_queue, _pool[i]);
	}
	AudioQueueDispose(_queue, true);
	delete _ringBuffer;
	_ringBuffer = 0;
	
	_started = NO;
	NSLog(@"Audio stopped");
}

- (void)pushPacket:(AVPacket*)packet
{
	std::unique_lock<std::mutex> lock(audioMutex);
	static AVFrame audioFrame;
	
	if (![self.decoder decodePacket:packet toFrame:&audioFrame]) {
		NSLog(@"error decode");
		return;
	}
	if (!_started) {
		BOOL success = [self startWithFrame:&audioFrame];
		if (!success) {
			NSLog(@"Error start audio!");
			return;
		}
	}
	writeRingBuffer(_ringBuffer, &audioFrame);
}

- (double)getCurrentTime
{
	if (_queue == NULL) return 0;
	
	AudioTimeStamp timeStamp;
	Boolean discontinuity;
	OSStatus err = AudioQueueGetCurrentTime(_queue, _timeLine, &timeStamp, &discontinuity);
	if (err == noErr && _dataFormat.mSampleRate != 0) {
		NSTimeInterval timeInterval = timeStamp.mSampleTime / _dataFormat.mSampleRate;
		return timeInterval;
	} else {
		return 0;
	}
}

- (int)decodedPacketCount
{
	if (_ringBuffer == NULL) {
		return 0;
	} else {
		return ringBufferCount(_ringBuffer);
	}
}

@end
