//
//  Util.m
//  neoTV-ffmpeg
//
//  Created by Сергей Сейтов on 07.06.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "Util.h"

@implementation Util
#include <mach/mach_time.h>

int64_t getUptimeInMilliseconds()
{
    const int64_t kOneMillion = 1000 * 1000;
    static mach_timebase_info_data_t s_timebase_info;
	
    if (s_timebase_info.denom == 0) {
        (void) mach_timebase_info(&s_timebase_info);
    }
	
    // mach_absolute_time() returns billionth of seconds,
    // so divide by one million to get milliseconds
    return (int64_t)((mach_absolute_time() * s_timebase_info.numer) / (kOneMillion * s_timebase_info.denom));
}

+ (NSData *)base64DataFromString: (NSString *)string
{
    unsigned long ixtext, lentext;
    unsigned char ch, inbuf[4], outbuf[3];
    short i, ixinbuf;
    Boolean flignore, flendtext = false;
    const unsigned char *tempcstring;
    NSMutableData *theData;
	
    if (string == nil)
    {
        return [NSData data];
    }
	
    ixtext = 0;
	
    tempcstring = (const unsigned char *)[string UTF8String];
	
    lentext = [string length];
	
    theData = [NSMutableData dataWithCapacity: lentext];
	
    ixinbuf = 0;
	
    while (true)
    {
        if (ixtext >= lentext)
        {
            break;
        }
		
        ch = tempcstring [ixtext++];
		
        flignore = false;
		
        if ((ch >= 'A') && (ch <= 'Z'))
        {
            ch = ch - 'A';
        }
        else if ((ch >= 'a') && (ch <= 'z'))
        {
            ch = ch - 'a' + 26;
        }
        else if ((ch >= '0') && (ch <= '9'))
        {
            ch = ch - '0' + 52;
        }
        else if (ch == '+')
        {
            ch = 62;
        }
        else if (ch == '=')
        {
            flendtext = true;
        }
        else if (ch == '/')
        {
            ch = 63;
        }
        else
        {
            flignore = true; 
        }
		
        if (!flignore)
        {
            short ctcharsinbuf = 3;
            Boolean flbreak = false;
			
            if (flendtext)
            {
                if (ixinbuf == 0)
                {
                    break;
                }
				
                if ((ixinbuf == 1) || (ixinbuf == 2))
                {
                    ctcharsinbuf = 1;
                }
                else
                {
                    ctcharsinbuf = 2;
                }
				
                ixinbuf = 3;
				
                flbreak = true;
            }
			
            inbuf [ixinbuf++] = ch;
			
            if (ixinbuf == 4)
            {
                ixinbuf = 0;
				
                outbuf[0] = (inbuf[0] << 2) | ((inbuf[1] & 0x30) >> 4);
                outbuf[1] = ((inbuf[1] & 0x0F) << 4) | ((inbuf[2] & 0x3C) >> 2);
                outbuf[2] = ((inbuf[2] & 0x03) << 6) | (inbuf[3] & 0x3F);
				
                for (i = 0; i < ctcharsinbuf; i++)
                {
                    [theData appendBytes: &outbuf[i] length: 1];
                }
            }
			
            if (flbreak)
            {
                break;
            }
        }
    }
	
    return theData;
}

+ (unsigned int) indexOf:(char) searchChar from:(NSString*) backingString {
	NSRange searchRange;
	searchRange.location=(unsigned int)searchChar;
	searchRange.length=1;
	NSRange foundRange = [backingString rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:searchRange]];
	return (unsigned int)foundRange.location;
}


@end
