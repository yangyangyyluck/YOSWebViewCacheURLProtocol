//
//  NSURLRequest+YOSMutableCopyWorkaround.h
//  YOSWebViewCacheURLProtocol
//
//  Created by yangyang on 16/7/12.
//  Copyright © 2016年 yy.inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#define WORKAROUND_MUTABLE_COPY_LEAK 1

@interface NSURLRequest (YOSMutableCopyWorkaround)

#if WORKAROUND_MUTABLE_COPY_LEAK

// required to workaround http://openradar.appspot.com/11596316
- (id)yos_mutableCopyWorkaround;

#endif

@end
