
#import "AppDelegate.h"

#import <UserNotifications/UserNotifications.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self requestNotificationPermission];

    return YES;
}

# pragma mark - Notification Permission

- (void)requestNotificationPermission {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionBadge | UNAuthorizationOptionSound;
    [center requestAuthorizationWithOptions:options
                          completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (!granted) {
            NSLog(@"Notification permission not granted: %@", error);
        }
    }];
}

@end
