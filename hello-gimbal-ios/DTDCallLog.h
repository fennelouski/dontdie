//
//  DTDCallLog.h
//  hello-gimbal-ios
//
//  Created by HAI on 1/3/16.
//  Copyright © 2016 Gimbal. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DTDCallLog : NSObject

@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, strong) NSDate *endTime;
@property (nonatomic, strong) NSString *to;
@property (nonatomic, strong) NSString *from;
@property (nonatomic) BOOL answered;
@property (nonatomic, strong) NSString *callType;
@property (nonatomic) BOOL fromMe;
@property (nonatomic, strong) NSString *name;
@property (nonatomic) NSTimeInterval maximumInterval;

- (NSString *)formattedDescription;

@end
