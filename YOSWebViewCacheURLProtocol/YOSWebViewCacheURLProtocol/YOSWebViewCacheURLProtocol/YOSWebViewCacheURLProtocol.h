//
//  YOSURLProtocol.h
//  NSURLProtocolTest
//
//  Created by yangyang on 16/7/8.
//  Copyright © 2016年 yy.inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface YOSWebViewCacheURLProtocol : NSURLProtocol

+ (void)additionHttpHeaders:(NSDictionary *)headers;

+ (void)clearAllCache;
+ (void)clearRecentCache;

@end
