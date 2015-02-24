//
//  VideoUtility.c
//  WD Content
//
//  Created by Sergey Seitov on 20.02.15.
//  Copyright (c) 2015 Sergey Seitov. All rights reserved.
//

#include "VideoUtility.h"
#include <assert.h>
#include <stdbool.h>

#define VDA_RB16(x)                     \
((((const uint8_t*)(x))[0] <<  8) |     \
((const uint8_t*)(x)) [1])

#define VDA_RB24(x)                     \
((((const uint8_t*)(x))[0] << 16) |     \
(((const uint8_t*)(x))[1] <<  8) |		\
((const uint8_t*)(x))[2])

#define VDA_RB32(x)                     \
((((const uint8_t*)(x))[0] << 24) |     \
(((const uint8_t*)(x))[1] << 16) |      \
(((const uint8_t*)(x))[2] <<  8) |      \
((const uint8_t*)(x))[3])

const uint8_t *avc_find_startcode_internal(const uint8_t *p, const uint8_t *end)
{
	const uint8_t *a = p + 4 - ((intptr_t)p & 3);
	
	for (end -= 3; p < a && p < end; p++)
	{
		if (p[0] == 0 && p[1] == 0 && p[2] == 1)
			return p;
	}
	
	for (end -= 3; p < end; p += 4)
	{
		uint32_t x = *(const uint32_t*)p;
		if ((x - 0x01010101) & (~x) & 0x80808080) // generic
		{
			if (p[1] == 0)
			{
				if (p[0] == 0 && p[2] == 1)
					return p;
				if (p[2] == 0 && p[3] == 1)
					return p+1;
			}
			if (p[3] == 0)
			{
				if (p[2] == 0 && p[4] == 1)
					return p+2;
				if (p[4] == 0 && p[5] == 1)
					return p+3;
			}
		}
	}
	
	for (end += 3; p < end; p++)
	{
		if (p[0] == 0 && p[1] == 0 && p[2] == 1)
			return p;
	}
	
	return end + 3;
}

const uint8_t *avc_find_startcode(const uint8_t *p, const uint8_t *end)
{
	const uint8_t *out= avc_find_startcode_internal(p, end);
	if (p<out && out<end && !out[-1])
		out--;
	return out;
}

const int avc_parse_nal_units(AVIOContext *pb, const uint8_t *buf_in, int size)
{
	const uint8_t *p = buf_in;
	const uint8_t *end = p + size;
	const uint8_t *nal_start, *nal_end;
	
	size = 0;
	nal_start = avc_find_startcode(p, end);
	while (nal_start < end)
	{
		while (!*(nal_start++));
		nal_end = avc_find_startcode(nal_start, end);
		avio_wb32(pb, (int)(nal_end - nal_start));
		avio_write(pb, nal_start, (int)(nal_end - nal_start));
		size += 4 + nal_end - nal_start;
		nal_start = nal_end;
	}
	return size;
}

const int avc_parse_nal_units_buf(const uint8_t *buf_in, uint8_t **buf, int *size)
{
	AVIOContext *pb;
	int ret = avio_open_dyn_buf(&pb);
	if (ret < 0)
		return ret;
	
	avc_parse_nal_units(pb, buf_in, *size);
	
	av_freep(buf);
	*size = avio_close_dyn_buf(pb, buf);
	return 0;
}

const int isom_write_avcc(AVIOContext *pb, const uint8_t *data, int len)
{
	// extradata from bytestream h264, convert to avcC atom data for bitstream
	if (len > 6)
	{
		/* check for h264 start code */
		if (VDA_RB32(data) == 0x00000001 || VDA_RB24(data) == 0x000001)
		{
			uint8_t *buf=NULL, *end, *start;
			uint32_t sps_size=0, pps_size=0;
			uint8_t *sps=0, *pps=0;
			
			int ret = avc_parse_nal_units_buf(data, &buf, &len);
			if (ret < 0)
				return ret;
			start = buf;
			end = buf + len;
			
			/* look for sps and pps */
			while (buf < end)
			{
				unsigned int size;
				uint8_t nal_type;
				size = VDA_RB32(buf);
				nal_type = buf[4] & 0x1f;
				if (nal_type == 7) /* SPS */
				{
					sps = buf + 4;
					sps_size = size;
				}
				else if (nal_type == 8) /* PPS */
				{
					pps = buf + 4;
					pps_size = size;
				}
				buf += size + 4;
			}
			assert(sps);
			
			avio_w8(pb, 1); /* version */
			avio_w8(pb, sps[1]); /* profile */
			avio_w8(pb, sps[2]); /* profile compat */
			avio_w8(pb, sps[3]); /* level */
			avio_w8(pb, 0xff); /* 6 bits reserved (111111) + 2 bits nal size length - 1 (11) */
			avio_w8(pb, 0xe1); /* 3 bits reserved (111) + 5 bits number of sps (00001) */
			
			avio_wb16(pb, sps_size);
			avio_write(pb, sps, sps_size);
			if (pps)
			{
				avio_w8(pb, 1); /* number of pps */
				avio_wb16(pb, pps_size);
				avio_write(pb, pps, pps_size);
			}
			av_free(start);
		}
		else
		{
			avio_write(pb, data, len);
		}
	}
	return 0;
}

bool convertAvcc(uint8_t* data, int dataSize, uint8_t** pDst)
{
	if ((data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1) || (data[0] == 0 && data[1] == 0 && data[2] == 1))
	{
		// video content is from x264 or from bytestream h264 (AnnexB format)
		// NAL reformating to bitstream format required
		AVIOContext *pb;
		if (avio_open_dyn_buf(&pb) < 0)
			return false;
		
		// create a valid avcC atom data from ffmpeg's extradata
		isom_write_avcc(pb, data, dataSize);
		
		// extract the avcC atom data into extradata getting size into extrasize
		avio_close_dyn_buf(pb, pDst);
		return true;
	} else {
		*pDst = data;
		return false;
	}
}
