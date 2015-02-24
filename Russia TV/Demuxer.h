//
//  Demuxer.h
//  WD Content
//
//  Created by Sergey Seitov on 19.01.15.
//  Copyright (c) 2015 Sergey Seitov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface Demuxer : NSObject

- (void)open:(NSString*)path completion:(void (^)(BOOL))completion;
- (void)close;
- (void)play;

- (CMSampleBufferRef)takeVideo;

@end

