//
//  DTDCallLog.h
//  Don't Die
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DTDCallLog : NSObject

@property (nonatomic, strong, nullable) NSDate *startTime;
@property (nonatomic, strong, nullable) NSDate *endTime;
@property (nonatomic, strong, nullable) NSString *to;
@property (nonatomic, strong, nullable) NSString *from;
@property (nonatomic) BOOL answered;
@property (nonatomic, strong, nullable) NSString *callType;
@property (nonatomic) BOOL fromMe;
@property (nonatomic, strong, nullable) NSString *name;

/// Builds a call log from the backend's missed-call JSON:
/// { "from": "+14045551234", "at": "2026-07-19T12:10:00.000Z", "inDriveMode": true }
+ (nullable instancetype)callLogWithServerDictionary:(NSDictionary *)dictionary;

- (NSString *)formattedDescription;

/// Caller's display string: the number formatted for reading, until the app
/// gains Contacts access to resolve real names.
- (NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
