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
#import "NSURLRequest+YOSMutableCopyWorkaround.h"

#define YOSWebViewCacheURLProtocolCachePath [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"YOSWebViewCacheURLProtocolCachePath"]

static NSString *const YOSHasHandledKey = @"YOSHasHandledKey";

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
    dispatch_async(dispatch_get_main_queue(), ^{
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
    });
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    
    if ([self _canUseCache:request]) {
        
        BOOL needHandled = ![NSURLProtocol propertyForKey:YOSHasHandledKey inRequest:request];
        
        return needHandled;
        
    } else {
        return NO;
    }
    
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    
    // case1. network not reachable
    // case2. image request use cache
    BOOL status1 = ![YOSWebViewCacheURLProtocol _isNetworkReachable:self.request];
    BOOL status2 =  ([YOSWebViewCacheURLProtocol _isImage:self.request] && [YOSWebViewCacheURLProtocol _isCached:self.request]);
    if (status1 || status2) {
        
        NSString *path = [YOSWebViewCacheURLProtocol _requestPath:self.request];
        
        void (^block)(YOSWebViewCache *cache) = ^(YOSWebViewCache *cache) {
            [self _dealWithCache:cache];
        };
        
        [YOSWebViewCacheURLProtocol _getCache:path completionBlock:block];
        
        
    } else {    // request
        NSMutableURLRequest *connectionRequest = [YOSWebViewCacheURLProtocol _requestWithAdditionHeaders:self.request];
        
        [YOSWebViewCacheURLProtocol setProperty:@YES forKey:YOSHasHandledKey inRequest:connectionRequest];
        
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
        
        // important!
        // mutableCopy make custom handledkey like origin request
        // mutableCopyWorkaround make custom handledkey resume
        // must use mutableCopyWorkaround
        NSMutableURLRequest *redirectableRequest = [request yos_mutableCopyWorkaround];
        
        // self.request = origin URL    like http://www.360buy.com  360buy will redirect to jd
        // request = modify URL         like http://www.jd.com
        // must use self.request
        NSString *cachePath = [YOSWebViewCacheURLProtocol _requestPath:self.request];
        
        YOSWebViewCache *cache = [YOSWebViewCache new];
        cache.date = [NSDate date];
        cache.response = response;
        cache.data = self.data;
        cache.redirectRequest = redirectableRequest;
        
        NSString *log = [NSString stringWithFormat:@"\r\rpropertyForKey in willSendRequest redirectRequest %@ ---  \r\r", redirectableRequest];
        
        [self _log:log];
        
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
    
    // only cached http status code = 200
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)self.response;
    if ([response isKindOfClass:[NSHTTPURLResponse class]] && response.statusCode == 200) {
        
        NSString *cachePath = [YOSWebViewCacheURLProtocol _requestPath:self.request];
        
        YOSWebViewCache *cache = [YOSWebViewCache new];
        cache.date = [NSDate date];
        cache.response = self.response;
        cache.data = self.data;
        
        [YOSWebViewCacheURLProtocol _saveCache:cache path:cachePath];
    }
    
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
        NSURLRequest *redirectRequest = cache.redirectRequest;
        
        NSString *log = [NSString stringWithFormat:@"\r\rpropertyForKey in _dealWithCache redirectRequest %@ ---  \r\r", redirectRequest];
        [self _log:log];
        
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

- (void)_log:(NSString *)string {
    //    NSLog(@"%@", string);
}

#pragma mark - private methods+

+ (NSMutableURLRequest *)_requestWithAdditionHeaders:(NSURLRequest *)request {
    
    NSMutableURLRequest *connectionRequest = [request yos_mutableCopyWorkaround];;
    
    [[YOSWebViewCacheURLProtocol httpHeaders] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL * _Nonnull stop) {
        
        [connectionRequest setValue:value forHTTPHeaderField:key];
        
    }];
    
    return connectionRequest;
}

+ (BOOL)_canUseCache:(NSURLRequest *)request {
    
    // webview use cache
    // only cache image
    if ([self _isSupportedSchemes:request] && [self _isWebView:request]) {
        return YES;
    } else {
        return NO;
    }
    
}

+ (BOOL)_isNetworkReachable:(NSURLRequest *)request {
    BOOL reachable = (BOOL) [[Reachability reachabilityWithHostName:request.URL.host] currentReachabilityStatus] != NotReachable;
    
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
    
    if (userAgent && [userAgent rangeOfString:@"AppleWebKit"].location != NSNotFound) {
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
    
    NSString *URLString = request.URL.absoluteString;
    
    if (request.HTTPBody) {
        NSString *param = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        if (param.length) {
            URLString = [URLString stringByAppendingString:param];
        }
    }
    
    NSString *path = URLString.yos_sha1;
    
    if ([self _isImage:request]) {
        path = [[self _imagePath] stringByAppendingPathComponent:path];
    } else {
        path = [[self _otherPath] stringByAppendingPathComponent:path];
    }
    
    return path;
}

#pragma mark - YOSWebViewCache

+ (void)_getCache:(NSString *)path completionBlock:(void (^)(YOSWebViewCache *cache))block {
    
    dispatch_async([YOSWebViewCacheURLProtocol ioQueue], ^{
        YOSWebViewCache *cache = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
        if (block) {
            block(cache);
        }
    });
}

+ (void)_saveCache:(YOSWebViewCache *)cache path:(NSString *)cachePath {
    dispatch_async([YOSWebViewCacheURLProtocol ioQueue], ^{
        [NSKeyedArchiver archiveRootObject:cache toFile:cachePath];
    });
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
        ioQueue = dispatch_queue_create("com.yoswebviewcache.concurrent", DISPATCH_QUEUE_CONCURRENT);
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
            
            void (^block)(YOSWebViewCache *cache) = ^(YOSWebViewCache *cache) {
                if ([cache.date compare:date] == NSOrderedAscending) {
                    
                    dispatch_async([self ioQueue], ^{
                        [[self fileManager] removeItemAtPath:completePath error:nil];
                    });
                    
                }
            };
            
            [self _getCache:completePath completionBlock:block];
        }
    });
    
}

@end
