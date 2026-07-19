//
//  DTDNetworkManager.h
//  Don't Die
//
//  Client for the Don't Die backend (see backend/ in this repository).
//  The backend base URL is read from the DTDAPIBaseURL key in Info.plist.
//

#import <Foundation/Foundation.h>

@class DTDCallLog;

NS_ASSUME_NONNULL_BEGIN

typedef void (^DTDDriveModeDisableCompletion)(NSArray<DTDCallLog *> *missedCalls,
                                              NSInteger rewardEarnedMB,
                                              NSInteger totalRewardMB,
                                              NSError * _Nullable error);

@interface DTDNetworkManager : NSObject

+ (instancetype)sharedNetworkManager;

/// Total data reward (MB) as last reported by the server.
@property (nonatomic, readonly) NSInteger totalRewardMB;

/// Registers this device with the backend if it has not been registered yet.
/// Safe to call repeatedly; credentials are persisted between launches.
- (void)registerDeviceIfNeeded;

/// Tells the server this device entered drive mode (starts a drive session).
+ (void)enableDriveModeOnServer;

/// Tells the server this device left drive mode. The completion block is
/// invoked on the main queue with the calls missed during the session and the
/// data reward earned.
+ (void)disableDriveModeOnServerWithCompletion:(nullable DTDDriveModeDisableCompletion)completion;

/// Links the user's US phone number so forwarded calls can be matched to this
/// device by the backend's Twilio webhook.
- (void)linkPhoneNumber:(NSString *)phoneNumber
             completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
