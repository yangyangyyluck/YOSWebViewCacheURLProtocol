//
//  NSString+Password.h
//  03.数据加密
//
//  Created by 刘凡 on 13-12-10.
//  Copyright (c) 2013年 itcast. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (Password)

- (NSString *)yos_md5;

- (NSString *)yos_sha1;

@end
