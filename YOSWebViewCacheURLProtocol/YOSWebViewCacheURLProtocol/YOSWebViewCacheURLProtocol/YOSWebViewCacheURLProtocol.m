//
//  YOSWebViewCacheURLProtocol.m
//  NSURLProtocolTest
//
//  Created by yangyang on 16/7/8.
//  Copyright © 2016年 yy.inc. All rights reserved.
//

#import "YOSWebViewCacheURLProtocol.h"
#import "Reachability.h"
#import "NSString+YOSCrypto.h"
#import "YOSWebViewCache.h"

#define YOSWebViewCacheURLProtocolCachePath [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"YOSWebViewCacheURLProtocolCachePath"]

static NSString *const YOSWebViewCacheURLProtocolHasHandledKey = @"YOSWebViewCacheURLProtocolHasHandledKey";

#define WORKAROUND_MUTABLE_COPY_LEAK 1

#if WORKAROUND_MUTABLE_COPY_LEAK
// required to workaround http://openradar.appspot.com/11596316
@interface NSURLRequest(MutableCopyWorkaround)

- (id) mutableCopyWorkaround;

@end

@implementation NSURLRequest(MutableCopyWorkaround)

- (id) mutableCopyWorkaround {
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
    
    return mutableURLRequest;
}

@end

#endif

static NSSet *supportedSchemes;
static dispatch_queue_t ioQueue;
static NSFileManager *fileManager;
static NSMutableDictionary *httpHeaders;

@interface YOSWebViewCacheURLProtocol ()

@property (nonatomic, strong, readonly) NSSet *supportedSchemes;

@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, strong) NSURLResponse *response;

- (void)_appendData:(NSData *)data;

@end

@implementation YOSWebViewCacheURLProtocol

+ (void)initialize {
    if ([YOSWebViewCacheURLProtocol class] == self) {
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:[self _imagePath]]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:[self _imagePath] withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:[self _otherPath]]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:[self _otherPath] withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        [self supportedSchemes];
        [self ioQueue];
        [self fileManager];
        
        NSLog(@"%@", [self _imagePath]);
        
    }
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    
    if ([self _canUseCache:request]) {
        
        BOOL hasHandled = [NSURLProtocol propertyForKey:YOSWebViewCacheURLProtocolHasHandledKey inRequest:request];
        
        if (hasHandled) {
            return NO;
        } else {
            return YES;
        }
        
    } else {
        return NO;
    }

}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    // can do some additions for http headerfield
    return request;
//    return [self _requestWithAdditionHeaders:request];
}

- (void)startLoading {
    
    // case1. network not reachable
    // case2. image request use cache
    BOOL status1 = ![YOSWebViewCacheURLProtocol _isNetworkReachable:self.request];
    BOOL status2 =  ([YOSWebViewCacheURLProtocol _isImage:self.request] && [YOSWebViewCacheURLProtocol _isCached:self.request]);
    if (status1 || status2) {
        
        YOSWebViewCache *cache = [YOSWebViewCacheURLProtocol _getCache:[YOSWebViewCacheURLProtocol _requestPath:self.request]];
        
        [self _dealWithCache:cache];
        
    } else {    // request
        NSMutableURLRequest *connectionRequest = [YOSWebViewCacheURLProtocol _requestWithAdditionHeaders:self.request];
        
        [YOSWebViewCacheURLProtocol setProperty:@YES forKey:YOSWebViewCacheURLProtocolHasHandledKey inRequest:connectionRequest];
        
        NSURLConnection *connection = [NSURLConnection connectionWithRequest:connectionRequest
                                                                    delegate:self];
        
        
        self.connection = connection;
    }
    
}

- (void)stopLoading {
    [self.connection cancel];
}

#pragma mark - NSURLConnectionDelegate

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response
{
    // Thanks to Nick Dowell https://gist.github.com/1885821
    if (response != nil) {
        NSMutableURLRequest *redirectableRequest = [request mutableCopyWorkaround];
        
        NSString *cachePath = [YOSWebViewCacheURLProtocol _requestPath:self.request];
        
        YOSWebViewCache *cache = [YOSWebViewCache new];
        cache.date = [NSDate date];
        cache.response = response;
        cache.data = self.data;
        cache.redirectRequest = redirectableRequest;
        
        BOOL hasHandled = [YOSWebViewCacheURLProtocol propertyForKey:YOSWebViewCacheURLProtocolHasHandledKey inRequest:request];
        
        BOOL hasHandled2 = [YOSWebViewCacheURLProtocol propertyForKey:YOSWebViewCacheURLProtocolHasHandledKey inRequest:redirectableRequest];
        
//        [YOSWebViewCacheURLProtocol setProperty:@NO forKey:YOSWebViewCacheURLProtocolHasHandledKey inRequest:redirectableRequest];
        
        NSLog(@"\r\rpropertyForKey in willSendRequest 1:%zi --- 2:%zi \r\r", hasHandled, hasHandled2);
        
        [YOSWebViewCacheURLProtocol _saveCache:cache path:cachePath];
        
        [[self client] URLProtocol:self wasRedirectedToRequest:redirectableRequest redirectResponse:response];
        
        return redirectableRequest;
    } else {
        return request;
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [[self client] URLProtocol:self didLoadData:data];
    [self _appendData:data];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    self.response = response;
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];  // We cache ourselves.
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [[self client] URLProtocolDidFinishLoading:self];
    
    NSString *cachePath = [YOSWebViewCacheURLProtocol _requestPath:self.request];
    
    YOSWebViewCache *cache = [YOSWebViewCache new];
    cache.date = [NSDate date];
    cache.response = self.response;
    cache.data = self.data;

    [YOSWebViewCacheURLProtocol _saveCache:cache path:cachePath];
    
    self.connection = nil;
    self.data = nil;
    self.response = nil;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [[self client] URLProtocol:self didFailWithError:error];
    
    self.connection = nil;
    self.data = nil;
    self.response = nil;
}

#pragma mark - private methods-

- (void)_dealWithCache:(YOSWebViewCache *)cache {
    
    if (cache) {
        NSData *data = cache.data;;
        NSURLResponse *response = cache.response;
        NSMutableURLRequest *redirectRequest = [cache.redirectRequest mutableCopyWorkaround];
        
//        [YOSWebViewCacheURLProtocol setProperty:@"god" forKey:YOSWebViewCacheURLProtocolHasHandledKey inRequest:redirectRequest];
        
        BOOL hasHandled = [YOSWebViewCacheURLProtocol propertyForKey:YOSWebViewCacheURLProtocolHasHandledKey inRequest:redirectRequest];
        
        NSLog(@"\r\rpropertyForKey in _dealWithCache 1:%zi ---  \r\r", hasHandled);
        
        if (redirectRequest) {
            [[self client] URLProtocol:self wasRedirectedToRequest:redirectRequest redirectResponse:response];
        } else {
            
            [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed]; // we handle caching ourselves.
            [[self client] URLProtocol:self didLoadData:data];
            [[self client] URLProtocolDidFinishLoading:self];
        }
    } else {
        [[self client] URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]];
    }
    
}

- (void)_appendData:(NSData *)newData {
    
    if (self.data == nil) {
        self.data = [newData mutableCopy];
    }
    else {
        [self.data appendData:newData];
    }
    
}

#pragma mark - private methods+

+ (NSMutableURLRequest *)_requestWithAdditionHeaders:(NSURLRequest *)request {
    
    BOOL hasHandled = [YOSWebViewCacheURLProtocol propertyForKey:YOSWebViewCacheURLProtocolHasHandledKey inRequest:request];
    
    NSMutableURLRequest *connectionRequest = nil;
    
    if (WORKAROUND_MUTABLE_COPY_LEAK) {
        connectionRequest = [request mutableCopyWorkaround];
    } else {
        connectionRequest = [request mutableCopy];
    }
    
    [[YOSWebViewCacheURLProtocol httpHeaders] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL * _Nonnull stop) {
        
        [connectionRequest setValue:value forHTTPHeaderField:key];
        
    }];
    
    return connectionRequest;
}

+ (BOOL)_canUseCache:(NSURLRequest *)request {

    // webview use cache
    if ([self _isSupportedSchemes:request] && [self _isWebView:request]) {
        return YES;
    } else {
        return NO;
    }
    
}

+ (BOOL)_isNetworkReachable:(NSURLRequest *)request {
    BOOL reachable = (BOOL) [[Reachability reachabilityWithHostName:request.URL.scheme] currentReachabilityStatus] != NotReachable;
    
    return reachable;
}

+ (BOOL)_isSupportedSchemes:(NSURLRequest *)request {

    NSString *scheme = request.URL.scheme.lowercaseString;
    
    if ([self.supportedSchemes containsObject:scheme]) {
        return YES;
    } else {
        return NO;
    }
    
}

+ (BOOL)_isImage:(NSURLRequest *)request {
    
    static NSSet *types;
    
    if (!types) {
        types = [NSSet setWithObjects:
                 @"png",
                 @"jpg",
                 @"jpeg",
                 @"svg",
                 @"tiff",
                 @"webp",
                 @"tiff",
                 @"bmp",
                 @"pcx",
                 @"tga",
                 @"exif",
                 @"fpx",
                 @"svg",
                 @"psd",
                 @"cdr",
                 @"pcd",
                 @"dfx",
                 @"ufo",
                 @"eps",
                 @"ai",
                 @"raw",
                 nil];
    }
    
    NSString *pathExtension = request.URL.absoluteString.lowercaseString.pathExtension;
    
    if (pathExtension.length && [types containsObject:pathExtension]) {
        return YES;
    } else {
        return NO;
    }
    
}

+ (BOOL)_isWebView:(NSURLRequest *)request {
    NSString *userAgent = [request valueForHTTPHeaderField:@"User-Agent"];
    
    if ([userAgent rangeOfString:@"AppleWebKit"].location != NSNotFound) {
        return YES;
    } else {
        return NO;
    }
}

+ (BOOL)_isCached:(NSURLRequest *)request {
    
    NSString *requestPath = [self _requestPath:request];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:requestPath]) {
        return YES;
    } else {
        return NO;
    }
    
}

#pragma mark - path

+ (NSString *)_imagePath {
    return [YOSWebViewCacheURLProtocolCachePath stringByAppendingPathComponent:@"image"];
}

+ (NSString *)_otherPath {
    return [YOSWebViewCacheURLProtocolCachePath stringByAppendingPathComponent:@"other"];
}

+ (NSString *)_requestPath:(NSURLRequest *)request {
    
    NSString *path = request.URL.absoluteString.yos_sha1;
//    NSString *path = request.URL.absoluteString.lastPathComponent;
//    [path stringByReplacingOccurrencesOfString:@":" withString:@"_"];
//    [path stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
//    [path stringByReplacingOccurrencesOfString:@"?" withString:@"__"];
//    [path stringByReplacingOccurrencesOfString:@"." withString:@"___"];
    
    if ([self _isImage:request]) {
        path = [[self _imagePath] stringByAppendingPathComponent:path];
    } else {
        path = [[self _otherPath] stringByAppendingPathComponent:path];
    }
    
    return path;
}

#pragma mark - YOSWebViewCache

+ (YOSWebViewCache * __nullable)_getCache:(NSString *)path {
    __block YOSWebViewCache *cache;
//    dispatch_sync([YOSWebViewCacheURLProtocol ioQueue], ^{
         cache = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
//    });
    
    return cache;
}

+ (void)_saveCache:(YOSWebViewCache *)cache path:(NSString *)cachePath {
//    dispatch_async([YOSWebViewCacheURLProtocol ioQueue], ^{
        [NSKeyedArchiver archiveRootObject:cache toFile:cachePath];
//    });
}

#pragma mark - getter & setter

+ (NSSet *)supportedSchemes {
    if (!supportedSchemes) {
        supportedSchemes = [NSSet setWithObjects:@"http", @"https", nil];
    }
    
    return supportedSchemes;
}

+ (dispatch_queue_t)ioQueue {
    if (!ioQueue) {
        ioQueue = dispatch_queue_create("com.yoswebviewcache.serial", DISPATCH_QUEUE_SERIAL);
    }
    
    return ioQueue;
}

+ (NSFileManager *)fileManager {
    if (!fileManager) {
        fileManager = [NSFileManager defaultManager];
    }
    
    return fileManager;
}

+ (NSMutableDictionary *)httpHeaders {
    if (!httpHeaders) {
        httpHeaders = [NSMutableDictionary dictionary];
    }
    
    return httpHeaders;
}

#pragma mark - public methods

+ (void)additionHttpHeaders:(NSDictionary *)headers {
    [[self httpHeaders] addEntriesFromDictionary:headers];
}

+ (void)clearAllCache {
    
    dispatch_async([self ioQueue], ^{
        [[self fileManager] removeItemAtPath:YOSWebViewCacheURLProtocolCachePath error:nil];
    });
    
}

+ (void)clearRecentCache {
    
    // remove cache before seven day
    NSTimeInterval interval = (3600 * 24 * -7);

    NSDate *date = [[NSDate date] dateByAddingTimeInterval:interval];
    
    NSDirectoryEnumerator *enumerator = [[self fileManager] enumeratorAtPath:YOSWebViewCacheURLProtocolCachePath];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSString *path in enumerator) {
            NSString *completePath = [YOSWebViewCacheURLProtocolCachePath stringByAppendingPathComponent:path];
            
            YOSWebViewCache *cache = [self _getCache:completePath];
            
            if ([cache.date compare:date] == NSOrderedAscending) {
                
                dispatch_async([self ioQueue], ^{
                    [[self fileManager] removeItemAtPath:completePath error:nil];
                });
                
            }
        }
    });
    
}

@end
