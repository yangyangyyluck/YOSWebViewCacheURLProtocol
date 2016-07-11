//
//  YOSWebViewCache.m
//  NSURLProtocolTest
//
//  Created by yangyang on 16/7/8.
//  Copyright © 2016年 yy.inc. All rights reserved.
//

#import "YOSWebViewCache.h"

static NSString *const kDateKey = @"date";
static NSString *const kDataKey = @"data";
static NSString *const kResponseKey = @"response";
static NSString *const kRedirectRequestKey = @"redirectRequest";

@implementation YOSWebViewCache

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.date forKey:kDateKey];
    [aCoder encodeObject:self.data forKey:kDataKey];
    [aCoder encodeObject:self.response forKey:kResponseKey];
    [aCoder encodeObject:self.redirectRequest forKey:kRedirectRequestKey];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    self.date = [aDecoder decodeObjectForKey:kDateKey];
    self.data = [aDecoder decodeObjectForKey:kDataKey];
    self.response = [aDecoder decodeObjectForKey:kResponseKey];
    self.redirectRequest = [aDecoder decodeObjectForKey:kRedirectRequestKey];
    
    return self;
}

@end