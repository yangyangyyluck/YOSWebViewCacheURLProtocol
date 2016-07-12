//
//  NSURLRequest+YOSMutableCopyWorkaround.m
//  YOSWebViewCacheURLProtocol
//
//  Created by yangyang on 16/7/12.
//  Copyright © 2016年 yy.inc. All rights reserved.
//

#import "NSURLRequest+YOSMutableCopyWorkaround.h"

@implementation NSURLRequest (YOSMutableCopyWorkaround)

#if WORKAROUND_MUTABLE_COPY_LEAK

- (id)yos_mutableCopyWorkaround {
    NSMutableURLRequest *mutableURLRequest = [[NSMutableURLRequest alloc] initWithURL:[self URL]
                                                                          cachePolicy:[self cachePolicy]
                                                                      timeoutInterval:[self timeoutInterval]];
    [mutableURLRequest setAllHTTPHeaderFields:[self allHTTPHeaderFields]];
    if ([self HTTPBodyStream]) {
        [mutableURLRequest setHTTPBodyStream:[self HTTPBodyStream]];
    } else {
        [mutableURLRequest setHTTPBody:[self HTTPBody]];
    }
    [mutableURLRequest setHTTPMethod:[self HTTPMethod]];
    
    [mutableURLRequest setMainDocumentURL:[self mainDocumentURL]];
    
    return mutableURLRequest;
}

- (NSString *)description {
    BOOL hasHandled = [NSURLProtocol propertyForKey:@"YOSHasHandledKey" inRequest:self];
    
    NSString *desc = [NSString stringWithFormat:@"\rhasHandled : %zi \rURL : %@ \rallHTTPHeaderFields : %@ \rmainDocumentURL : %@ \rcachePolicy : %zi \rHTTPBody : %@ \rHTTPBodyStream : %@ \rHTTPMethod : %@ \rtimeoutInterval : %f", hasHandled, self.URL, self.allHTTPHeaderFields, self.mainDocumentURL, self.cachePolicy, self.HTTPBody, self.HTTPBodyStream, self.HTTPMethod, self.timeoutInterval];
    
    return desc;
}

#endif

@end
