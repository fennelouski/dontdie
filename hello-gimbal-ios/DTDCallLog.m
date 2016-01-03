//
//  DTDCallLog.m
//  hello-gimbal-ios
//
//  Created by HAI on 1/3/16.
//  Copyright © 2016 Gimbal. All rights reserved.
//

#import "DTDCallLog.h"

@implementation DTDCallLog

- (NSString *)formattedDescription {
    NSMutableString *formattedDescription = [[NSMutableString alloc] initWithString:@""];
    
    if (self.startTime) {
        [formattedDescription appendFormat:@"\nStart Time: %@", self.startTime];
    }
    
    if (self.endTime) {
        [formattedDescription appendFormat:@"\nEnd Time:   %@", self.endTime];
    }
    
    if (self.to) {
        [formattedDescription appendFormat:@"\nTo:   %@", self.to];
    }
    
    if (self.from) {
        [formattedDescription appendFormat:@"\nFrom: %@", self.from];
    }
    
    if (self.callType) {
        [formattedDescription appendFormat:@"\nCall Type: %@", self.callType];
    }
    
    [formattedDescription appendFormat:@"\nCall was %@answered", self.answered ? @"" : @"not "];
    
    [formattedDescription appendFormat:@"\nCall was %@from me", self.fromMe ? @"" : @"not "];
    
    return formattedDescription;
}

@end
