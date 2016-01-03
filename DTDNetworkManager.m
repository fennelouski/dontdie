//
//  DTDNetworkManager.m
//  hello-gimbal-ios
//
//  Created by HAI on 1/3/16.
//  Copyright © 2016 Gimbal. All rights reserved.
//

#import "DTDNetworkManager.h"
#import "DTDCallLog.h"

@interface DTDNetworkManager () <NSURLConnectionDelegate, NSURLConnectionDataDelegate>

@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@property (nonatomic, strong) NSMutableDictionary *callLogs;
@property (nonatomic, strong) NSMutableDictionary *lateCallLogs;

@end

static NSString * const Consumer_key = @"mYnxvWlp7kPV8faDkv1iWdsUj1fnGFSI";
static NSString * const Consumer_secret = @"0xxoP1HdNj2BkmWF";
static NSString * const rootURL = @"http://api.foundry.att.net:9001/oauth/client_credential/accesstoken?grant_type=client_credentials";
static NSString * const userName = @"4047241415@private.att.net";
static NSString * const phoneNumber = @"4047241415";

@implementation DTDNetworkManager {
    NSString *accessToken;
    NSNumber *pageIndex;
    NSNumber *pageSize;
}

+ (instancetype)sharedNetworkManager {
    static DTDNetworkManager *sharedDataManager;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDataManager = [[DTDNetworkManager alloc] init];
    });
    
    return sharedDataManager;
}

- (instancetype)init {
    self = [super init];
    
    if (self) {
        self.dateFormatter = [[NSDateFormatter alloc] init];
        self.dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        [self getOAuthToken];
    }
    
    return self;
}

- (void)getOAuthToken {
    NSString *clientID = Consumer_key;
    NSString *secret = Consumer_secret;
    
    NSString *authString = [NSString stringWithFormat:@"%@:%@", clientID, secret];
    NSData * authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *credentials = [NSString stringWithFormat:@"Basic %@", [authData base64EncodedStringWithOptions:0]];
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    [configuration setHTTPAdditionalHeaders:@{ @"Accept": @"application/json", @"Accept-Language": @"en_US", @"Content-Type": @"application/x-www-form-urlencoded", @"Authorization": credentials }];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:rootURL]];
    request.HTTPMethod = @"POST";
    
    NSString *dataString = @"grant_type=client_credentials";
    NSData *theData = [dataString dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    
    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromData:theData completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSDictionary *response = [NSDictionary dictionaryWithDictionary:[NSJSONSerialization JSONObjectWithData:data options:0 error:&error]];
            NSLog(@"data = %@", response.allKeys);
            
            accessToken = [response objectForKey:@"access_token"];
            NSLog(@"accessToken: %@", accessToken);
            
            [self getCallHistory];
        }
    }];
    
    [task resume];
    
    
    
}

#pragma mark - Call History

- (void)getCallHistory {
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"http://api.foundry.att.net:9001/a1/nca/callhistory/%@", phoneNumber]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", accessToken] forHTTPHeaderField:@"Authorization"];
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSData *data = [@"" dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    
    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromData:data completionHandler:^(NSData *data,
                                                                                                            NSURLResponse *response,
                                                                                                            NSError *error) {
        if (!error) {
            NSLog(@"%@", [[NSDictionary dictionaryWithDictionary:[NSJSONSerialization JSONObjectWithData:data options:0 error:&error]] class]);
            NSMutableDictionary *responseDictionary = [NSMutableDictionary dictionaryWithDictionary:[NSJSONSerialization JSONObjectWithData:data options:0 error:&error]];
            NSArray *logs = [responseDictionary objectForKey:@"logs"];
            
            NSLog(@"logs: %@", logs);
            
            for (NSDictionary *dictionary in logs) {
                NSLog(@"%@\n%@", [dictionary class], dictionary);
                [self processCallDictionary:[NSDictionary dictionaryWithDictionary:dictionary]];
                
                [task cancel];
                
                [self callEventSubscription];
            }
            
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                NSLog(@"%@", self.callLogs.allKeys);
            });
        } else {
            NSLog(@"error on second call: %@", error);
        }
    }];
    
    [task resume];
}

- (void)processCallDictionary:(NSDictionary *)callDictionary {
    DTDCallLog *callLog = [DTDCallLog new];
    
    NSString *startTimeString = [callDictionary objectForKey:@"startTime"];
    NSDate *startTime = [self.dateFormatter dateFromString:startTimeString];
    if (startTime) {
        callLog.startTime = startTime;
    } else {
        NSLog(@"startTimeString: %@", startTimeString);
    }
    
    NSString *endTimeString = [callDictionary objectForKey:@"endTime"];
    NSDate *endTime = [self.dateFormatter dateFromString:endTimeString];
    if (endTime) {
        callLog.endTime = endTime;
    } else {
        NSLog(@"endTimeString: %@", endTimeString);
    }
    
    NSString *to = [callDictionary objectForKey:@"to"];
    if (to) {
        callLog.to = to;
    } else {
        NSLog(@"Not to anyone?");
    }
    
    
    NSString *from = [callDictionary objectForKey:@"from"];
    if (from) {
        callLog.from = from;
    } else {
        NSLog(@"Not from anyone?");
    }
    
    NSString *answeredString = [callDictionary objectForKey:@"answered"];
    callLog.answered = [answeredString boolValue];
    
    NSString *callType = [callDictionary objectForKey:@"calltype"];
    if (callType) {
        callLog.callType = callType;
    } else {
        NSLog(@"No call type? Transponder?, %@", callDictionary.allKeys);
    }
    
    if ([callLog.from containsString:phoneNumber]) {
        callLog.fromMe = YES;
        
        DTDCallLog *oldCallLog = [self.callLogs objectForKey:callLog.to];
        if (!oldCallLog || (oldCallLog && [callLog.endTime timeIntervalSinceDate:oldCallLog.endTime] > 0 && ![oldCallLog.callType containsString:@"missed"])) {
            [self.callLogs setObject:callLog forKey:callLog.to];
        }
    } else if ([callLog.to containsString:phoneNumber]) {
        callLog.fromMe = NO;
        
        DTDCallLog *oldCallLog = [self.callLogs objectForKey:callLog.from];
        if (!oldCallLog || (oldCallLog && [callLog.endTime timeIntervalSinceDate:oldCallLog.endTime] > 0 && ![oldCallLog.callType containsString:@"missed"])) {
            [self.callLogs setObject:callLog forKey:callLog.from];
        }
    } else {
        NSLog(@"Neither Number is from me!");
    }
    
    NSString *name = @"Rob";
    
    if ([callLog.from containsString:@"9387"]) {
        name = @"Grandma";
    } else if ([callLog.from containsString:@"8365"]) {
        name = @"Katie";
    } else if ([callLog.from containsString:@"9250"]) {
        name = @"Ryan M.";
    } else if ([callLog.from containsString:@"535"]) {
        name = @"Paul C.";
    } else if ([callLog.from containsString:@"1428"]) {
        name = @"Jonathan";
    } else if ([callLog.from containsString:@"1429"]) {
        name = @"Jen";
    } else if ([callLog.from containsString:@"1427"]) {
        name = @"Leeann";
    }
    
    callLog.name = name;
    
    callLog.maximumInterval = 60 * (arc4random_uniform(4)) + arc4random_uniform(24) * 3600;
    
    NSLog(@"%@", callLog.formattedDescription);
    
    if (callLog.maximumInterval < fabs([callLog.endTime timeIntervalSinceNow])) {
        if ([callLog.from containsString:phoneNumber]) {
            callLog.fromMe = YES;
            
            DTDCallLog *oldCallLog = [self.lateCallLogs objectForKey:callLog.to];
            if (!oldCallLog || (oldCallLog && [callLog.endTime timeIntervalSinceDate:oldCallLog.endTime] > 0 && ![oldCallLog.callType containsString:@"missed"])) {
                [self.lateCallLogs setObject:callLog forKey:callLog.to];
            }
        } else if ([callLog.to containsString:phoneNumber]) {
            callLog.fromMe = NO;
            
            DTDCallLog *oldCallLog = [self.lateCallLogs objectForKey:callLog.from];
            if (!oldCallLog || (oldCallLog && [callLog.endTime timeIntervalSinceDate:oldCallLog.endTime] > 0 && ![oldCallLog.callType containsString:@"missed"])) {
                [self.lateCallLogs setObject:callLog forKey:callLog.from];
            }
        } else {
            NSLog(@"Neither Number is from me!");
        }
    }
}



#pragma mark - Call Event Subscription

- (void)callEventSubscription {
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"http://api.foundry.att.net:9001/a1/nca/subscription/callEvent/%@", phoneNumber]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", accessToken]
   forHTTPHeaderField:@"Authorization"];
    
    [request setValue:@"Called"
   forHTTPHeaderField:@"addressDirection"];
    
    
    NSArray *criteria = @[@"CalledNumber"];
    
    NSError *error;
    NSData *offersJSONData = [NSJSONSerialization dataWithJSONObject:criteria
                                                             options:NSJSONWritingPrettyPrinted error:&error];
    
    NSString *jsonStringCriteria = [[NSString alloc] initWithData:offersJSONData encoding:NSUTF8StringEncoding] ;

    [request setValue:jsonStringCriteria
   forHTTPHeaderField:@"criteria"];
    
    
    [request setValue:@"http://my3pas:8080/beinformed/ofthiscall"
   forHTTPHeaderField:@"url"];
    
    
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSData *data = [@"" dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    
    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request
                                                         fromData:data
                                                completionHandler:^(NSData *data,
                                                                    NSURLResponse *response,
                                                                    NSError *error) {
                                                    if (response) {
                                                        NSLog(@"Response: %@", response);
                                                    }
                                                    
                                                    if (!error) {
                                                        NSLog(@"No Error! %@", [[NSDictionary dictionaryWithDictionary:[NSJSONSerialization JSONObjectWithData:data options:0 error:&error]] class]);
                                                        NSMutableDictionary *responseDictionary = [NSMutableDictionary dictionaryWithDictionary:[NSJSONSerialization JSONObjectWithData:data
                                                                                                                                                                                options:0
                                                                                                                                                                                  error:&error]];
                                                        NSLog(@"Data returned: %@", data);
                                                        NSArray *logs = [responseDictionary objectForKey:@"logs"];
                                                        
                                                        NSLog(@"logs: %@", responseDictionary);
                                                        
                                                        for (NSDictionary *dictionary in logs) {
                                                            NSLog(@"%@\n%@", [dictionary class], dictionary);
                                                            [self processCallDictionary:[NSDictionary dictionaryWithDictionary:dictionary]];
                                                        }
                                                    } else {
                                                        NSLog(@"error on second call: %@", error);
                                                    }
                                                    
                                                    [task cancel];
                                                }];
    
    [task resume];
}

#pragma mark - Call Control 

- (void)cancelCall {
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"http://api.foundry.att.net:9001/a1/nca/callcontrol/call/%@", phoneNumber]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", accessToken] forHTTPHeaderField:@"Authorization"];
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSData *data = [@"" dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    
    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request fromData:data completionHandler:^(NSData *data,
                                                                                                            NSURLResponse *response,
                                                                                                            NSError *error) {
        if (!error) {
            NSLog(@"%@", [[NSDictionary dictionaryWithDictionary:[NSJSONSerialization JSONObjectWithData:data options:0 error:&error]] class]);
            NSMutableDictionary *responseDictionary = [NSMutableDictionary dictionaryWithDictionary:[NSJSONSerialization JSONObjectWithData:data options:0 error:&error]];
            NSArray *logs = [responseDictionary objectForKey:@"logs"];
            
            NSLog(@"logs: %@", logs);
            
            for (NSDictionary *dictionary in logs) {
                NSLog(@"%@\n%@", [dictionary class], dictionary);
                [self processCallDictionary:[NSDictionary dictionaryWithDictionary:dictionary]];
                
                [task cancel];
            }
            
            NSLog(@"%@", self.callLogs.allKeys);
        } else {
            NSLog(@"error on second call: %@", error);
        }
    }];
    
    [task resume];
}


#pragma mark - Connection Delegate

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog(@"%@\ndidFailWithError: %@", connection, error);
    [connection cancel];
}

- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)connection {
    NSLog(@"connectionShouldUseCredentialStorage: %@", connection);
    return NO;
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    NSLog(@"connection: %@\n\nwillSendRequestForAuthenticationChallenge: %@", connection, challenge);
}

-(void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge{
    if([challenge previousFailureCount] == 0) {
        NSURLCredential *newCredential;
        newCredential=[NSURLCredential credentialWithUser:Consumer_key password:Consumer_secret persistence:NSURLCredentialPersistenceNone];
        [[challenge sender] useCredential:newCredential forAuthenticationChallenge:challenge];}
    else {
        [[challenge sender] cancelAuthenticationChallenge:challenge];
        NSLog(@"Bad Username Or Password");
    }
}





- (nullable NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(nullable NSURLResponse *)response {
    NSLog(@"connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(nullable NSURLResponse *)response");
    
    return nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSLog(@"connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response: %@", response);
    [connection cancel];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    NSLog(@"connection:(NSURLConnection *)connection didReceiveData:(NSData *)data: %@", data);
}

- (nullable NSInputStream *)connection:(NSURLConnection *)connection needNewBodyStream:(NSURLRequest *)request {
    NSLog(@"connection:(NSURLConnection *)connection needNewBodyStream:(NSURLRequest *)request: %@", request);
    return nil;
}

- (void)connection:(NSURLConnection *)connection
   didSendBodyData:(NSInteger)bytesWritten
 totalBytesWritten:(NSInteger)totalBytesWritten
totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite {
    NSLog(@"Stuff");
}



#pragma mark - Public Methods

- (NSDictionary *)callLogs {
    if (!_callLogs) {
        _callLogs = [NSMutableDictionary new];
    }
    
    return _callLogs;
}

+ (NSDictionary *)callLogs {
    return [[DTDNetworkManager sharedNetworkManager] callLogs];
}

- (NSMutableDictionary *)lateCallLogs {
    if (!_lateCallLogs) {
        _lateCallLogs = [NSMutableDictionary new];
    }
    
    return _lateCallLogs;
}

+ (NSMutableDictionary *)lateCallLogs {
    return [[DTDNetworkManager sharedNetworkManager] lateCallLogs];
}

+ (void)update {
    [[DTDNetworkManager sharedNetworkManager] update];
}

- (void)update {
    [self.lateCallLogs removeAllObjects];
    for (NSString *phoneNumberKey in [[DTDNetworkManager sharedNetworkManager] callLogs].allKeys) {
        DTDCallLog *callLog = [[[DTDNetworkManager sharedNetworkManager] callLogs] objectForKey:phoneNumberKey];
        
        if (callLog.maximumInterval < fabs([callLog.endTime timeIntervalSinceNow])) {
            if ([callLog.from containsString:phoneNumber]) {
                callLog.fromMe = YES;
                
                DTDCallLog *oldCallLog = [self.lateCallLogs objectForKey:callLog.to];
                if (!oldCallLog || (oldCallLog && [callLog.endTime timeIntervalSinceDate:oldCallLog.endTime] > 0 && ![oldCallLog.callType containsString:@"missed"])) {
                    [self.lateCallLogs setObject:callLog forKey:callLog.to];
                }
            } else if ([callLog.to containsString:phoneNumber]) {
                callLog.fromMe = NO;
                
                DTDCallLog *oldCallLog = [self.lateCallLogs objectForKey:callLog.from];
                if (!oldCallLog || (oldCallLog && [callLog.endTime timeIntervalSinceDate:oldCallLog.endTime] > 0 && ![oldCallLog.callType containsString:@"missed"])) {
                    [self.lateCallLogs setObject:callLog forKey:callLog.from];
                }
            } else {
                NSLog(@"Neither Number is from me!");
            }
        }
    }
}



@end
