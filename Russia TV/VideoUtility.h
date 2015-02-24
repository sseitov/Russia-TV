//
//  VideoUtility.h
//  WD Content
//
//  Created by Sergey Seitov on 20.02.15.
//  Copyright (c) 2015 Sergey Seitov. All rights reserved.
//

#ifndef __WD_Content__VideoUtility__
#define __WD_Content__VideoUtility__

#include <_types.h>
#include <stdbool.h>

#include "libavformat/avio.h"

/* H264 extradata
 
 bits
 8   version ( always 0x01 )
 8   avc profile ( sps[0][1] )
 8   avc compatibility ( sps[0][2] )
 8   avc level ( sps[0][3] )
 6   reserved ( all bits on )
 2   NALULengthSizeMinusOne
 3   reserved ( all bits on )
 5   number of SPS NALUs (usually 1)
 repeated once per SPS:
 16     SPS size
 variable   SPS NALU data
 8   number of PPS NALUs (usually 1)
 repeated once per PPS
 16    PPS size
 variable PPS NALU data
 
 */

#pragma pack(push,1)

struct SpsHeader
{
	uint8_t	version;               // ( always 0x01 )
	uint8_t	avc_profile;                // ( sps[0][1] )
	uint8_t	avc_compatibility;          // ( sps[0][2] )
	uint8_t	avc_level;                  // ( sps[0][3] )
	uint8_t	reserved1:6;                // ( all bits on )
	uint8_t	NALULengthSizeMinusOne:2;
	uint8_t	reserved2:3;                // ( all bits on )
	uint8_t	number_of_SPS_NALUs:5;      // (usually 1)
	unsigned short	SPS_size;
};

struct PpsHeader
{
	uint8_t     number_of_PPS_NALUs;        // (usually 1)
	unsigned short    PPS_size;
};

#pragma pack(pop)

const int avc_parse_nal_units(AVIOContext *pb, const uint8_t *buf_in, int size);
bool convertAvcc(uint8_t* data, int dataSize, uint8_t** pDst);

/* MPEG-4 esds (elementary stream descriptor) */
typedef struct {
	int version;
	long flags;
	
	uint16_t esid;
	uint8_t  stream_priority;
	
	uint8_t  objectTypeId;
	uint8_t  streamType;
	uint32_t bufferSizeDB;
	uint32_t maxBitrate;
	uint32_t avgBitrate;
	
	int      decoderConfigLen;
	uint8_t* decoderConfig;
} quicktime_esds_t;

quicktime_esds_t* quicktime_set_esds(const uint8_t * decoderConfig, int decoderConfigLen);
void quicktime_write_esds(AVIOContext *pb, quicktime_esds_t *esds);

#endif /* defined(__WD_Content__VideoUtility__) */
