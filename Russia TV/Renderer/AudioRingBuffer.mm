//
//  RingBuffer.cpp
//  vTV
//
//  Created by Sergey Seitov on 25.08.13.
//  Copyright (c) 2013 V-Channel. All rights reserved.
//

#include "AudioRingBuffer.h"
#include "Util.h"

AudioRingBuffer::AudioRingBuffer(int elementsCount, int bufferSize)
:_count(elementsCount+1), _bufferSize(bufferSize), _start(0), _end(0), _stopped(false)
{
	_data = (char*)calloc(_count, _bufferSize);
	_framePTS = (int64_t*)calloc(_count, sizeof(int64_t));
	for (int i=0; i<_count; i++) {
		_framePTS[i] = AV_NOPTS_VALUE;
	}
	_currentPTSTime = _currentPTS = AV_NOPTS_VALUE;
}

AudioRingBuffer::~AudioRingBuffer()
{
	free(_data);
	free(_framePTS);
}

bool readRingBuffer(AudioRingBuffer* rb, AudioQueueBufferRef& buffer)
{
	std::unique_lock<std::mutex> lock(rb->_mutex);
	if (!rb->_overflow.wait_for(lock,  std::chrono::milliseconds(10), [&rb]() { return (!rb->isEmpty() || rb->_stopped);})) {
		rb->_currentPTS = AV_NOPTS_VALUE;
		rb->_currentPTSTime = AV_NOPTS_VALUE;
		return false;
	}
	if (rb->_stopped) return false;
	
	buffer->mAudioDataByteSize = rb->_bufferSize;
	memcpy(buffer->mAudioData, rb->_data + rb->_start*rb->_bufferSize, rb->_bufferSize);
	rb->_currentPTS = rb->_framePTS[rb->_start];
	rb->_currentPTSTime = getUptimeInMilliseconds();
	
	rb->_start = (rb->_start + 1) % rb->_count;
	rb->_overflow.notify_one();
	
	return true;
}

void writeRingBuffer(AudioRingBuffer* rb, AVFrame* audioFrame)
{
	std::unique_lock<std::mutex> lock(rb->_mutex);
	rb->_overflow.wait(lock, [&rb]() { return (!rb->isFull() || rb->_stopped);});
	if (rb->_stopped) return;

	char *output = rb->_data + rb->_end*rb->_bufferSize;
	
	if (audioFrame->channels == 1 || audioFrame->format == AV_SAMPLE_FMT_S16) {
		memcpy(output, audioFrame->data[0], rb->_bufferSize);
	} else { // downmix float multichannel
		StereoFloatSample* outputBuffer = (StereoFloatSample*)output;
		if (audioFrame->channels == 6) {
			float* leftChannel = (float*)audioFrame->data[0];
			float* rightChannel = (float*)audioFrame->data[1];
			float* centerChannel = (float*)audioFrame->data[2];
			float* leftBackChannel = (float*)audioFrame->data[3];
			float* rightBackChannel = (float*)audioFrame->data[4];
			float* lfeChannel = (float*)audioFrame->data[5];
			for (int i=0; i<audioFrame->nb_samples; i++) {
				outputBuffer[i].left = leftChannel[i] + centerChannel[i]/2.0 + lfeChannel[i]/2.0 + (-leftBackChannel[i] - rightBackChannel[i])/2.0;
				outputBuffer[i].right = rightChannel[i] + centerChannel[i]/2.0 + lfeChannel[i]/2.0 + (leftBackChannel[i] + rightBackChannel[i])/2.0;
			}
		} else if (audioFrame->channels == 2) {
			float* leftChannel = (float*)audioFrame->data[0];
			float* rightChannel = (float*)audioFrame->data[1];
			for (int i=0; i<audioFrame->nb_samples; i++) {
				outputBuffer[i].left = leftChannel[i];
				outputBuffer[i].right = rightChannel[i];
			}
		}
	}
	rb->_framePTS[rb->_end] = audioFrame->pts;
    rb->_end = (rb->_end + 1) % rb->_count;
}

void resetRingBuffer(AudioRingBuffer* rb)
{
	std::unique_lock<std::mutex> lock(rb->_mutex);
	rb->_stopped = true;
	rb->_overflow.notify_one();
}

void flushRingBuffer(AudioRingBuffer* rb)
{
	std::unique_lock<std::mutex> lock(rb->_mutex);
	rb->_start = rb->_end = 0;
	rb->_overflow.notify_one();
}

void ringBufferPTSWithTime(AudioRingBuffer* rb, int64_t* ppts, int64_t* ptime)
{
	std::unique_lock<std::mutex> lock(rb->_mutex);
	*ppts = rb->_currentPTS;
	*ptime = rb->_currentPTSTime;
}

int64_t ringBufferPTS(AudioRingBuffer* rb)
{
	std::unique_lock<std::mutex> lock(rb->_mutex);
	return rb->_currentPTS;
}

int ringBufferCount(AudioRingBuffer* rb)
{
	if (rb->_end > rb->_start) {
		return rb->_end - rb->_start;
	} else {
		return rb->_end + rb->_count - rb->_start;
	}
}

