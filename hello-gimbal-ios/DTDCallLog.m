//
//  DTDCallLog.m
//  Don't Die
//

#import "DTDCallLog.h"

@implementation DTDCallLog

+ (instancetype)callLogWithServerDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *from = [dictionary[@"from"] isKindOfClass:[NSString class]] ? dictionary[@"from"] : nil;
    if (from.length == 0) {
        return nil;
    }

    DTDCallLog *callLog = [DTDCallLog new];
    callLog.from = from;
    callLog.callType = @"missed";
    callLog.answered = NO;
    callLog.fromMe = NO;
    callLog.startTime = [self dateFromISO8601String:dictionary[@"at"]];
    callLog.name = [callLog displayName];
    return callLog;
}

+ (NSDate *)dateFromISO8601String:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }

    static NSDateFormatter *fractionalFormatter;
    static NSDateFormatter *plainFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLocale *posix = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        NSTimeZone *utc = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];

        fractionalFormatter = [NSDateFormatter new];
        fractionalFormatter.locale = posix;
        fractionalFormatter.timeZone = utc;
        fractionalFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

        plainFormatter = [NSDateFormatter new];
        plainFormatter.locale = posix;
        plainFormatter.timeZone = utc;
        plainFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    });

    return [fractionalFormatter dateFromString:value] ?: [plainFormatter dateFromString:value];
}

- (NSString *)displayName {
    if (self.name.length > 0) {
        return self.name;
    }

    NSString *digits = [[self.from componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
    if (digits.length == 11 && [digits hasPrefix:@"1"]) {
        digits = [digits substringFromIndex:1];
    }
    if (digits.length == 10) {
        return [NSString stringWithFormat:@"(%@) %@-%@",
                [digits substringToIndex:3],
                [digits substringWithRange:NSMakeRange(3, 3)],
                [digits substringFromIndex:6]];
    }

    return self.from ?: @"Unknown caller";
}

- (NSString *)formattedDescription {
    NSMutableString *formattedDescription = [NSMutableString new];

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
