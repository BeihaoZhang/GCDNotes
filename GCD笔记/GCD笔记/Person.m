//
//  Person.m
//  GCD笔记
//
//  Created by Lincoln on 2018/1/29.
//  Copyright © 2018年 Lincoln. All rights reserved.
//

#import "Person.h"

@implementation Person

- (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static Person *p;
    dispatch_once(&onceToken, ^{
        p = [[Person alloc] init];
    });
    return p;
}

@end
