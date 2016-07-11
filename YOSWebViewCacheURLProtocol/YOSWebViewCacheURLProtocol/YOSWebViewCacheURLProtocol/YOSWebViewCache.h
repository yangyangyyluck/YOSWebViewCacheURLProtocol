//
//  YOSWebViewCache.h
//  NSURLProtocolTest
//
//  Created by yangyang on 16/7/8.
//  Copyright © 2016年 yy.inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface YOSWebViewCache : NSObject <NSCoding>

@property (nonatomic, readwrite, strong) NSDate *date;

@property (nonatomic, readwrite, strong) NSData *data;

@property (nonatomic, readwrite, strong) NSURLResponse *response;

@property (nonatomic, readwrite, strong) NSURLRequest *redirectRequest;

@end
