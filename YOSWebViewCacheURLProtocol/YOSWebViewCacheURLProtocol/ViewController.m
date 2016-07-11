//
//  ViewController.m
//  YOSWebViewCacheURLProtocol
//
//  Created by yangyang on 16/7/11.
//  Copyright © 2016年 yy.inc. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@property (nonatomic, strong) UIWebView *webView;

@property (nonatomic, strong) UIButton *button;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    CGSize size = [UIScreen mainScreen].bounds.size;
    
    self.webView = [UIWebView new];
    
    self.webView.frame = CGRectMake(0, 0, size.width, size.height);
    [self.view addSubview:self.webView];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://www.jd.com"]];
    [self.webView loadRequest:request];
    
    self.button = [UIButton new];
    self.button.frame = CGRectMake(100, 100, 100, 100);
    self.button.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.7];
    [self.button addTarget:self action:@selector(tappedButton) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.button];
}

- (void)tappedButton {
    NSLog(@"\r--tappedButton--\r");
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

