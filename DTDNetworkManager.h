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

+ (NSDictionary *)callLogs;
+ (NSMutableDictionary *)lateCallLogs;

+ (void)enableDriveModeOnServer;
+ (void)disableDriveModeOnServer;

@end
