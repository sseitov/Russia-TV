//
//  Util.h
//  neoTV-ffmpeg
//
//  Created by Сергей Сейтов on 07.06.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
int64_t getUptimeInMilliseconds();

@interface Util : NSObject {
	
}

+ (unsigned int) indexOf:(char) searchChar from:(NSString*) backingString;
+ (NSData *)base64DataFromString: (NSString *)string;

@end
