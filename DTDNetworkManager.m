//
//  DTDNetworkManager.m
//  Don't Die
//

#import "DTDNetworkManager.h"
#import "DTDCallLog.h"

static NSTimeInterval const DTDRequestTimeout = 12.0;

static NSString * const DTDAPIBaseURLInfoPlistKey = @"DTDAPIBaseURL";
static NSString * const DTDDefaultAPIBaseURL = @"https://api.dontdie.app";

static NSString * const DTDDeviceIdentifierDefaultsKey = @"DTDDeviceIdentifier";
static NSString * const DTDDeviceTokenDefaultsKey = @"DTDDeviceToken";
static NSString * const DTDTotalRewardDefaultsKey = @"DTDTotalRewardMB";

@interface DTDNetworkManager ()

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *baseURLString;
@property (nonatomic, copy, nullable) NSString *deviceIdentifier;
@property (nonatomic, copy, nullable) NSString *deviceToken;
@property (nonatomic) BOOL registrationInFlight;
@property (nonatomic, strong) NSMutableArray<void (^)(BOOL registered)> *pendingOperations;
@property (nonatomic, readwrite) NSInteger totalRewardMB;

@end

@implementation DTDNetworkManager

+ (instancetype)sharedNetworkManager {
    static DTDNetworkManager *sharedManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[DTDNetworkManager alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = DTDRequestTimeout;
        _session = [NSURLSession sessionWithConfiguration:configuration];

        NSString *configuredURL = [[NSBundle mainBundle] objectForInfoDictionaryKey:DTDAPIBaseURLInfoPlistKey];
        _baseURLString = configuredURL.length > 0 ? configuredURL : DTDDefaultAPIBaseURL;

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _deviceIdentifier = [defaults stringForKey:DTDDeviceIdentifierDefaultsKey];
        _deviceToken = [defaults stringForKey:DTDDeviceTokenDefaultsKey];
        _totalRewardMB = [defaults integerForKey:DTDTotalRewardDefaultsKey];
        _pendingOperations = [NSMutableArray new];

        [self registerDeviceIfNeeded];
    }
    return self;
}

#pragma mark - Registration

- (void)registerDeviceIfNeeded {
    [self performWhenRegistered:nil];
}

// Runs the operation once the device has credentials, registering first if
// needed. Operations queued while registration is in flight all run when it
// finishes.
- (void)performWhenRegistered:(nullable void (^)(BOOL registered))operation {
    if (self.deviceIdentifier.length > 0 && self.deviceToken.length > 0) {
        if (operation) operation(YES);
        return;
    }

    if (operation) {
        [self.pendingOperations addObject:[operation copy]];
    }

    if (self.registrationInFlight) {
        return;
    }
    self.registrationInFlight = YES;

    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                      path:@"/v1/devices"
                                                      body:@{ @"platform": @"ios", @"appVersion": appVersion }
                                             authenticated:NO];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.registrationInFlight = NO;

            NSDictionary *json = [self jsonFromData:data response:response error:error];
            NSString *deviceIdentifier = json[@"deviceId"];
            NSString *deviceToken = json[@"deviceToken"];

            BOOL registered = deviceIdentifier.length > 0 && deviceToken.length > 0;
            if (registered) {
                self.deviceIdentifier = deviceIdentifier;
                self.deviceToken = deviceToken;
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setObject:deviceIdentifier forKey:DTDDeviceIdentifierDefaultsKey];
                [defaults setObject:deviceToken forKey:DTDDeviceTokenDefaultsKey];
            } else {
                NSLog(@"Device registration failed: %@", error ?: json);
            }

            NSArray *operations = [self.pendingOperations copy];
            [self.pendingOperations removeAllObjects];
            for (void (^pending)(BOOL) in operations) {
                pending(registered);
            }
        });
    }];
    [task resume];
}

#pragma mark - Drive mode

+ (void)enableDriveModeOnServer {
    DTDNetworkManager *manager = [DTDNetworkManager sharedNetworkManager];
    [manager performWhenRegistered:^(BOOL registered) {
        if (!registered) return;
        [manager sendDriveModeEnabled:YES completion:nil];
    }];
}

+ (void)disableDriveModeOnServerWithCompletion:(DTDDriveModeDisableCompletion)completion {
    DTDNetworkManager *manager = [DTDNetworkManager sharedNetworkManager];
    [manager performWhenRegistered:^(BOOL registered) {
        if (!registered) {
            if (completion) {
                completion(@[], 0, manager.totalRewardMB,
                           [NSError errorWithDomain:@"DTDNetworkManager"
                                               code:1
                                           userInfo:@{ NSLocalizedDescriptionKey: @"Device is not registered with the server." }]);
            }
            return;
        }
        [manager sendDriveModeEnabled:NO completion:completion];
    }];
}

- (void)sendDriveModeEnabled:(BOOL)enabled completion:(nullable DTDDriveModeDisableCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/v1/devices/%@/drive-mode", self.deviceIdentifier];
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                      path:path
                                                      body:@{ @"enabled": @(enabled) }
                                             authenticated:YES];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = [self jsonFromData:data response:response error:error];

        NSMutableArray<DTDCallLog *> *missedCalls = [NSMutableArray new];
        NSInteger rewardEarnedMB = 0;
        NSInteger totalRewardMB = self.totalRewardMB;

        if (json) {
            for (NSDictionary *callDictionary in [json[@"missedCalls"] isKindOfClass:[NSArray class]] ? json[@"missedCalls"] : @[]) {
                DTDCallLog *callLog = [DTDCallLog callLogWithServerDictionary:callDictionary];
                if (callLog) {
                    [missedCalls addObject:callLog];
                }
            }
            rewardEarnedMB = [json[@"rewardEarnedMB"] integerValue];
            NSDictionary *device = [json[@"device"] isKindOfClass:[NSDictionary class]] ? json[@"device"] : nil;
            if (device[@"totalRewardMB"]) {
                totalRewardMB = [device[@"totalRewardMB"] integerValue];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.totalRewardMB = totalRewardMB;
            [[NSUserDefaults standardUserDefaults] setInteger:totalRewardMB forKey:DTDTotalRewardDefaultsKey];

            if (completion) {
                completion(missedCalls, rewardEarnedMB, totalRewardMB, json ? nil : error);
            }
        });
    }];
    [task resume];
}

#pragma mark - Phone number linking

- (void)linkPhoneNumber:(NSString *)phoneNumber
             completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    [self performWhenRegistered:^(BOOL registered) {
        if (!registered) {
            if (completion) completion(NO, nil);
            return;
        }

        NSString *path = [NSString stringWithFormat:@"/v1/devices/%@/phone-number", self.deviceIdentifier];
        NSMutableURLRequest *request = [self requestWithMethod:@"PUT"
                                                          path:path
                                                          body:@{ @"phoneNumber": phoneNumber }
                                                 authenticated:YES];

        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSDictionary *json = [self jsonFromData:data response:response error:error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(json != nil, error);
            });
        }];
        [task resume];
    }];
}

#pragma mark - Request helpers

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method
                                      path:(NSString *)path
                                      body:(nullable NSDictionary *)body
                             authenticated:(BOOL)authenticated {
    NSURL *url = [NSURL URLWithString:[self.baseURLString stringByAppendingString:path]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request.HTTPMethod = method;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    if (authenticated && self.deviceToken.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.deviceToken]
       forHTTPHeaderField:@"Authorization"];
    }

    if (body) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    }

    return request;
}

// Returns the parsed JSON dictionary for a 2xx response, nil otherwise.
- (nullable NSDictionary *)jsonFromData:(nullable NSData *)data
                               response:(nullable NSURLResponse *)response
                                  error:(nullable NSError *)error {
    if (error || data.length == 0) {
        NSLog(@"Request failed: %@", error);
        return nil;
    }

    NSInteger statusCode = 0;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        statusCode = ((NSHTTPURLResponse *)response).statusCode;
    }

    NSError *parseError;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    if (![json isKindOfClass:[NSDictionary class]]) {
        NSLog(@"Unexpected response body: %@", parseError);
        return nil;
    }

    if (statusCode < 200 || statusCode >= 300) {
        NSLog(@"Server returned %zd: %@", statusCode, json);
        return nil;
    }

    return json;
}

@end
