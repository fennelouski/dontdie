//
//  DTDNetworkManager.h
//  hello-gimbal-ios
//
//  Created by HAI on 1/3/16.
//  Copyright © 2016 Gimbal. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DTDNetworkManager : NSObject

+ (instancetype)sharedNetworkManager;

+ (void)update;

- (void)getCallHistory;

+ (NSDictionary *)callLogs;
+ (NSMutableDictionary *)lateCallLogs;
- (NSMutableArray *)missedCallsSince:(NSDate *)date;

+ (void)enableDriveModeOnServer;
+ (void)disableDriveModeOnServer;

@end
