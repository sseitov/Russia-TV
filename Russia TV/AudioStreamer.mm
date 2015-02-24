//
//  AudioStreamer.m
//  WD Content
//
//  Created by Sergey Seitov on 23.02.15.
//  Copyright (c) 2015 Sergey Seitov. All rights reserved.
//

#import "AudioStreamer.h"
#include <AudioToolbox/AudioToolbox.h>

#define kNumAQBufs 16
#define kAQDefaultBufSize 2048
#define kAQMaxPacketDescs 512

#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 50

#define CheckError(a,b) if(HasError(a, b)) return NO;

static NSString* fourChar2String(FourCharCode aCode)
{
	aCode = CFSwapInt32BigToHost(aCode);
	return [NSString stringWithFormat:@"%4.4s", (char*)&aCode];
}

static BOOL HasError(OSStatus error, NSString *operation)
{
	if (error == noErr) return NO;
	NSLog(@"%@ FAILED: %@", operation, fourChar2String(error));
	return YES;
}

@interface AudioStreamer () {
	
	AudioQueueRef audioQueue;
	AudioQueueTimelineRef timeLine;
	AudioFileStreamID streamID;
	AudioQueueBufferRef audioQueueBuffer[kNumAQBufs];				// audio queue buffers
	AudioStreamPacketDescription packetDescs[kAQMaxPacketDescs];	// packet descriptions for enqueuing audio
	
	AudioStreamBasicDescription asbd;	// description of the audio
	UInt32 packetBufferSize;
	
	unsigned int fillBufferIndex;		// the index of the audioQueueBuffer that is being filled
	int bytesFilled;					// how many bytes have been filled
	int packetsFilled;					// how many packets have been filled
	bool inuse[kNumAQBufs];				// flags to indicate that a buffer is still in use
}

@property (atomic) BOOL running;
@property (strong, nonatomic) NSCondition *queueBufferReadyCondition;	// a condition varable for handling the inuse flags

- (BOOL)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
					 fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
								  ioFlags:(UInt32 *)ioFlags;

- (void)handleAudioPackets:(const void *)inInputData
			   numberBytes:(UInt32)inNumberBytes
			 numberPackets:(UInt32)inNumberPackets
		packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;

- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
							  buffer:(AudioQueueBufferRef)inBuffer;

@end

static void ASPropertyListenerProc(void *							inClientData,
								   AudioFileStreamID				inAudioFileStream,
								   AudioFileStreamPropertyID		inPropertyID,
								   UInt32 *							ioFlags)
{
	AudioStreamer* streamer = (__bridge AudioStreamer *)inClientData;
	[streamer handlePropertyChangeForFileStream:inAudioFileStream fileStreamPropertyID:inPropertyID ioFlags:ioFlags];
}

static void ASPacketsProc(		void *							inClientData,
								UInt32							inNumberBytes,
								UInt32							inNumberPackets,
								const void *					inInputData,
								AudioStreamPacketDescription	*inPacketDescriptions)
{
	AudioStreamer* streamer = (__bridge AudioStreamer *)inClientData;
	[streamer handleAudioPackets:inInputData numberBytes:inNumberBytes numberPackets:inNumberPackets packetDescriptions:inPacketDescriptions];
}

static void ASAudioQueueOutputCallback(void*				inClientData,
									   AudioQueueRef			inAQ,
									   AudioQueueBufferRef		inBuffer)
{
	AudioStreamer* streamer = (__bridge AudioStreamer*)inClientData;
	[streamer handleBufferCompleteForQueue:inAQ buffer:inBuffer];
}

@implementation AudioStreamer

- (id)init
{
	self = [super init];
	if (self) {
		_queueBufferReadyCondition = [[NSCondition alloc] init];
	}
	return self;
}

- (BOOL)openWithContext:(AVCodecContext*)codecContext
{
	AudioFileTypeID fileTypeHint;
	switch (codecContext->codec_id) {
		case AV_CODEC_ID_MP2:
			NSLog(@"AV_CODEC_ID_MP2 NOT SUPPORTED");
			return NO;
		case AV_CODEC_ID_MP3:
			NSLog(@"AV_CODEC_ID_MP3");
			fileTypeHint = kAudioFileMP3Type;
			break;
		case AV_CODEC_ID_AAC:
			NSLog(@"AV_CODEC_ID_AAC");
			fileTypeHint = kAudioFileAAC_ADTSType;
			break;
		case AV_CODEC_ID_AC3:
			NSLog(@"AV_CODEC_ID_AC3 NOT SUPPORTED");
			return NO;
		case AV_CODEC_ID_DTS:
			NSLog(@"AV_CODEC_ID_DTS NOT SUPPORTED");
			return NO;
		default:
			NSLog(@"Unknown codec %d", codecContext->codec_id);
			return NO;
	}
    
	memset(&asbd, 0, sizeof(asbd));
    packetBufferSize = 0;
    fillBufferIndex = 0;
    bytesFilled = 0;
    packetsFilled = 0;
    for (int i=0; i<kNumAQBufs; i++) {
        inuse[i] = false;
    }

    self.stopped = NO;
    self.running = NO;
	CheckError(AudioFileStreamOpen((__bridge void*)self,
								   ASPropertyListenerProc,
								   ASPacketsProc,
								   fileTypeHint,
								   &streamID), @"AudioFileStreamOpen");
	self.context = codecContext;
	return YES;
}

- (void)close
{
	if (self.stopped) return;
    self.stopped = YES;
    self.running = NO;
    
	AudioQueueStop(audioQueue, true);
	for (unsigned int i = 0; i < kNumAQBufs; ++i)
	{
		AudioQueueFreeBuffer(audioQueue, audioQueueBuffer[i]);
        audioQueueBuffer[i] = NULL;
	}
	
	AudioQueueDispose(audioQueue, true);
    audioQueue = NULL;
    AudioFileStreamClose(streamID);
    streamID = NULL;
}

- (void)decodePacket:(AVPacket*)packet
{
	AudioFileStreamParseBytes(streamID, packet->size, packet->data, 0);
}

- (double)currentTime
{
	if (audioQueue == NULL) return 0;
	
	AudioTimeStamp timeStamp;
	Boolean discontinuity;
	OSStatus err = AudioQueueGetCurrentTime(audioQueue, timeLine, &timeStamp, &discontinuity);
	if (err == noErr && asbd.mSampleRate != 0) {
		NSTimeInterval timeInterval = timeStamp.mSampleTime / asbd.mSampleRate;
		return timeInterval;
	} else {
		return 0;
	}
}

#pragma mark - Callback handlers

- (BOOL)createQueue
{
	// create the audio queue
	CheckError(AudioQueueNewOutput(&asbd,
								   ASAudioQueueOutputCallback,
								   (__bridge void*)self,
								   NULL,
								   NULL,
								   0,
								   &audioQueue), @"AudioQueueNewOutput");
	AudioQueueCreateTimeline(audioQueue, &timeLine);

	// get the packet size if it is available
	UInt32 sizeOfUInt32 = sizeof(UInt32);
	OSStatus err = AudioFileStreamGetProperty(streamID,
											  kAudioFileStreamProperty_PacketSizeUpperBound,
											  &sizeOfUInt32,
											  &packetBufferSize);
	if (err != noErr || packetBufferSize == 0) {
		err = AudioFileStreamGetProperty(streamID,
										 kAudioFileStreamProperty_MaximumPacketSize,
										 &sizeOfUInt32,
										 &packetBufferSize);
		if (err != noErr || packetBufferSize == 0) {
			// No packet size available, just use the default
			packetBufferSize = kAQDefaultBufSize;
		}
	}
	
	// allocate audio queue buffers
	for (unsigned int i = 0; i < kNumAQBufs; ++i) {
		CheckError(AudioQueueAllocateBuffer(audioQueue,
											packetBufferSize,
											&audioQueueBuffer[i]), @"AudioQueueAllocateBuffer");
	}
	
	// get the cookie size
	UInt32 cookieSize;
	Boolean writable;
	CheckError(AudioFileStreamGetPropertyInfo(streamID,
											  kAudioFileStreamProperty_MagicCookieData,
											  &cookieSize,
											  &writable), @"AudioFileStreamGetPropertyInfo kAudioFileStreamProperty_MagicCookieData");
	
	// get the cookie data
	void* cookieData = calloc(1, cookieSize);
	CheckError(AudioFileStreamGetProperty(streamID,
										  kAudioFileStreamProperty_MagicCookieData,
										  &cookieSize,
										  cookieData), @"AudioFileStreamGetProperty kAudioFileStreamProperty_MagicCookieData");
	
	// set the cookie on the queue.
	CheckError(AudioQueueSetProperty(audioQueue,
									 kAudioQueueProperty_MagicCookie,
									 cookieData,
									 cookieSize), @"AudioQueueSetProperty kAudioQueueProperty_MagicCookie");
	free(cookieData);
	
	return YES;
}

- (BOOL)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
					 fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
								  ioFlags:(UInt32 *)ioFlags
{
	NSLog(@"Handle Property is %@", fourChar2String(inPropertyID));
	if (self.stopped) {
		return NO;
	}
	
	if (inPropertyID == kAudioFileStreamProperty_ReadyToProducePackets)
	{
	}
	else if (inPropertyID == kAudioFileStreamProperty_DataOffset)
	{
	}
	else if (inPropertyID == kAudioFileStreamProperty_AudioDataByteCount)
	{
	}
	else if (inPropertyID == kAudioFileStreamProperty_FileFormat) {
	}
	else if (inPropertyID == kAudioFileStreamProperty_MagicCookieData) {
	}
	else if (inPropertyID == kAudioFileStreamProperty_ChannelLayout) {
	}
	else if (inPropertyID == kAudioFileStreamProperty_DataFormat)
	{
		if (asbd.mSampleRate == 0) {
			UInt32 asbdSize = sizeof(asbd);
			
			// get the stream format.
			CheckError(AudioFileStreamGetProperty(inAudioFileStream,
												  kAudioFileStreamProperty_DataFormat,
												  &asbdSize,
												  &asbd), @"AudioFileStreamGetProperty");
		}
	}
	else if (inPropertyID == kAudioFileStreamProperty_FormatList)
	{
		Boolean outWriteable;
		UInt32 formatListSize;
		CheckError(AudioFileStreamGetPropertyInfo(inAudioFileStream,
												  kAudioFileStreamProperty_FormatList,
												  &formatListSize,
												  &outWriteable), @"AudioFileStreamGetPropertyInfo kAudioFileStreamProperty_FormatList");
		
		AudioFormatListItem *formatList = (AudioFormatListItem*)malloc(formatListSize);
		CheckError(AudioFileStreamGetProperty(inAudioFileStream,
											  kAudioFileStreamProperty_FormatList,
											  &formatListSize,
											  formatList), @"AudioFileStreamGetProperty kAudioFileStreamProperty_FormatList");
		
		for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem)) {
			AudioStreamBasicDescription pasbd = formatList[i].mASBD;
			NSLog(@"AAC format: %@", fourChar2String(pasbd.mFormatID));
			if (pasbd.mFormatID == kAudioFormatMPEG4AAC_HE || pasbd.mFormatID == kAudioFormatMPEG4AAC_HE_V2) {
				asbd = pasbd;
				break;
			}
		}
		free(formatList);
	}
	return YES;
}

- (void)handleAudioPackets:(const void *)inInputData
			   numberBytes:(UInt32)inNumberBytes
			 numberPackets:(UInt32)inNumberPackets
		packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions
{
	if (self.stopped) {
		return;
	}
	
	if (!audioQueue) {
		[self createQueue];
	}

	// the following code assumes we're streaming VBR data. for CBR data, the second branch is used.
	if (inPacketDescriptions)
	{
		for (int i = 0; i < inNumberPackets; ++i) {
			SInt64 packetOffset = inPacketDescriptions[i].mStartOffset;
			SInt64 packetSize   = inPacketDescriptions[i].mDataByteSize;
			size_t bufSpaceRemaining;
			
			// If the audio was terminated before this point, then
			// exit.
			if (self.stopped) {
				return;
			}
			
			if (packetSize > packetBufferSize) {
				NSLog(@"ERROR: AS_AUDIO_BUFFER_TOO_SMALL");
				return;
			}
			
			bufSpaceRemaining = packetBufferSize - bytesFilled;
			
			// if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
			if (bufSpaceRemaining < packetSize) {
				[self enqueueBuffer];
			}
			
			// If the audio was terminated while waiting for a buffer, then
			// exit.
			if (self.stopped) {
				return;
			}
			
			//
			// If there was some kind of issue with enqueueBuffer and we didn't
			// make space for the new audio data then back out
			//
			if (bytesFilled + packetSize > packetBufferSize) {
				return;
			}
			
			// copy data to the audio queue buffer
			AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
			memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)inInputData + packetOffset, packetSize);
			
			// fill out packet description
			packetDescs[packetsFilled] = inPacketDescriptions[i];
			packetDescs[packetsFilled].mStartOffset = bytesFilled;
			// keep track of bytes filled and packets filled
			bytesFilled += packetSize;
			packetsFilled += 1;
			
			// if that was the last free packet description, then enqueue the buffer.
			size_t packetsDescsRemaining = kAQMaxPacketDescs - packetsFilled;
			if (packetsDescsRemaining == 0) {
				[self enqueueBuffer];
			}
		}
	}
	else
	{
		size_t offset = 0;
		while (inNumberBytes) {
			// if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
			size_t bufSpaceRemaining = kAQDefaultBufSize - bytesFilled;
			if (bufSpaceRemaining < inNumberBytes) {
				[self enqueueBuffer];
			}
			
			// If the audio was terminated while waiting for a buffer, then
			// exit.
			if (self.stopped) {
				return;
			}
			
			bufSpaceRemaining = kAQDefaultBufSize - bytesFilled;
			size_t copySize;
			if (bufSpaceRemaining < inNumberBytes) {
				copySize = bufSpaceRemaining;
			} else {
				copySize = inNumberBytes;
			}
			
			//
			// If there was some kind of issue with enqueueBuffer and we didn't
			// make space for the new audio data then back out
			//
			if (bytesFilled > packetBufferSize) {
				return;
			}
			
			// copy data to the audio queue buffer
			AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
			memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)inInputData + offset, copySize);
			
			
			// keep track of bytes filled and packets filled
			bytesFilled += copySize;
			packetsFilled = 0;
			inNumberBytes -= copySize;
			offset += copySize;
		}
	}
}

- (BOOL)enqueueBuffer
{
	if (self.stopped) {
		return NO;
	}
	
	inuse[fillBufferIndex] = true;		// set in use flag
	
	// enqueue buffer
	AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
	fillBuf->mAudioDataByteSize = bytesFilled;
	
	if (packetsFilled) {
		CheckError(AudioQueueEnqueueBuffer(audioQueue,
										   fillBuf,
										   packetsFilled,
										   packetDescs), @"AudioQueueEnqueueBuffer");
	} else {
		CheckError(AudioQueueEnqueueBuffer(audioQueue,
										   fillBuf,
										   0,
										   NULL), @"AudioQueueEnqueueBuffer");
	}
	
	if (!self.running) {
		CheckError(AudioQueueStart(audioQueue, NULL), @"AudioQueueStart");
		self.running = YES;
	}
	
	// go to next buffer
	if (++fillBufferIndex >= kNumAQBufs)
		fillBufferIndex = 0;
	bytesFilled = 0;		// reset bytes filled
	packetsFilled = 0;		// reset packets filled
	
	// wait until next buffer is not in use
	[_queueBufferReadyCondition lock];
	while (inuse[fillBufferIndex]) {
		[_queueBufferReadyCondition wait];
	}
    [_queueBufferReadyCondition unlock];
	return YES;
}

- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
							  buffer:(AudioQueueBufferRef)inBuffer
{
	unsigned int bufIndex = -1;
	for (unsigned int i = 0; i < kNumAQBufs; ++i) {
		if (inBuffer == audioQueueBuffer[i]) {
			bufIndex = i;
			break;
		}
	}
	
	[_queueBufferReadyCondition lock];
	if (bufIndex == -1) {
		NSLog(@"ERROR: AUDIO QUEUE BUFFER MISMATCH");
	} else {
		inuse[bufIndex] = false;
	}
	[_queueBufferReadyCondition signal];
    [_queueBufferReadyCondition unlock];
}

@end
