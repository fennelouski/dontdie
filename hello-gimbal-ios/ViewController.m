//
//  ViewController.m
//  Don't Die
//
//  Created by HAI on 1/3/16.
//  Copyright © 2016 Nathan Fennel. All rights reserved.
//

#import "ViewController.h"

#import "DTDEnabledView.h"
#import "DTDDisabledView.h"

#import <Gimbal/Gimbal.h>

#import <CoreMotion/CoreMotion.h>
#import <CoreLocation/CoreLocation.h>

#import "DTDNetworkManager.h"

@interface ViewController () <GMBLPlaceManagerDelegate, CLLocationManagerDelegate>
@property (nonatomic) GMBLPlaceManager *placeManager;
@property (nonatomic) NSMutableArray *placeEvents;

@property (nonatomic, strong) DTDDisabledView *disabledView;
@property (nonatomic, strong) DTDEnabledView *enabledView;

@property (nonatomic, strong) UIToolbar *invisibleToolbar;

@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) CMDeviceMotion *deviceMotion;

@property (nonatomic, strong) CLLocationManager *locationManager;

@property (nonatomic, strong) UILabel *speedLabel;

@end

@implementation ViewController {
    BOOL _driveModeEnabled;
    NSInteger _stoppedUpdateCount;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.placeEvents = [NSMutableArray new];
    
    [DTDNetworkManager sharedNetworkManager];
    
    [Gimbal setAPIKey:@"8ea0b2a4-dd93-4c19-b54d-95ccc8706770"
              options:nil];
    
    self.placeManager = [GMBLPlaceManager new];
    self.placeManager.delegate = self;
    [GMBLPlaceManager startMonitoring];
    
    [GMBLCommunicationManager startReceivingCommunications];
    
    [self.view addSubview:self.disabledView];
    [self.view addSubview:self.enabledView];
    [self.view addSubview:self.speedLabel];
    [self.view addSubview:self.invisibleToolbar];
    
    if (!self.motionManager) {
        self.motionManager = [[CMMotionManager alloc] init];
        [self.motionManager startAccelerometerUpdates];
        
//        /*NSTimer *timer1 = */[NSTimer scheduledTimerWithTimeInterval:0.3
//                                                           target:self
//                                                         selector:@selector(updateMotion)
//                                                         userInfo:nil
//                                                          repeats:YES];
    }
    
    if (!self.locationManager) {
        CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
        switch (status) {
            case kCLAuthorizationStatusNotDetermined: {
                NSLog(@"User still thinking granting location access!");
                [self.locationManager startUpdatingLocation]; // this will access location automatically if user granted access manually. and will not show apple's request alert twice. (Tested)
            } break;
            case kCLAuthorizationStatusDenied: {
                [self.locationManager stopUpdatingLocation];
            } break;
            case kCLAuthorizationStatusAuthorizedWhenInUse:
            case kCLAuthorizationStatusAuthorizedAlways: {
                [self.locationManager startUpdatingLocation]; //Will update location immediately
            } break;
            default:
                break;
        }
        
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.distanceFilter = kCLDistanceFilterNone;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;

        [self.locationManager startUpdatingLocation];
        [self.locationManager requestWhenInUseAuthorization];
        
    }
}




#pragma mark - Abled Views

- (DTDDisabledView *)disabledView {
    if (!_disabledView) {
        _disabledView = [[DTDDisabledView alloc] initWithFrame:self.view.bounds];
    }
    
    return _disabledView;
}

- (DTDEnabledView *)enabledView {
    if (!_enabledView) {
        _enabledView = [[DTDEnabledView alloc] initWithFrame:self.view.bounds];
        _enabledView.alpha = 0.0f;
    }
    
    return _enabledView;
}

- (UIToolbar *)invisibleToolbar {
    if (!_invisibleToolbar) {
        _invisibleToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.0f,
                                                                        self.view.frame.size.height - 44.0f,
                                                                        self.view.frame.size.width,
                                                                        44.0f)];
        [_invisibleToolbar setBackgroundImage:[UIImage new]
                           forToolbarPosition:UIBarPositionAny
                                   barMetrics:UIBarMetricsDefault];
        [_invisibleToolbar setShadowImage:[UIImage new]
                       forToolbarPosition:UIBarPositionAny];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(invisibleToolbarTapped:)];
        [_invisibleToolbar addGestureRecognizer:tap];
        
        UISwipeGestureRecognizer *leftSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                        action:@selector(disableDriveMode)];
        leftSwipe.direction = UISwipeGestureRecognizerDirectionLeft;
        [_invisibleToolbar addGestureRecognizer:leftSwipe];
        
        UISwipeGestureRecognizer *rightSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                         action:@selector(enableDriveMode)];
        rightSwipe.direction = UISwipeGestureRecognizerDirectionRight;
        [_invisibleToolbar addGestureRecognizer:rightSwipe];
    }
    
    return _invisibleToolbar;
}

- (void)enableDriveMode {
    _driveModeEnabled = YES;

    NSTimeInterval delay = 3.0f + arc4random_uniform(6);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateAbledViews];
    });
}

- (void)disableDriveMode {
    _driveModeEnabled = NO;

    NSTimeInterval delay = 2.0f;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateAbledViews];
    });
}

- (void)invisibleToolbarTapped:(UITapGestureRecognizer *)tap {
    _driveModeEnabled = !_driveModeEnabled;
    
    NSTimeInterval delay = 2.0f;
    if (_driveModeEnabled) {
        delay = 3.0f + arc4random_uniform(6);
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateAbledViews];
    });
}


- (UILabel *)speedLabel {
    if (!_speedLabel) {
        _speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0f,
                                                                self.view.frame.size.height * 0.5f,
                                                                self.view.frame.size.width,
                                                                44.0f)];
        _speedLabel.textAlignment = NSTextAlignmentCenter;
        _speedLabel.textColor = [UIColor whiteColor];
        _speedLabel.font = [UIFont systemFontOfSize:24.0f];
    }
    
    return _speedLabel;
}


#pragma mark - Update Abled Views

- (void)updateAbledViews {
    if (_driveModeEnabled) {
        [UIView animateWithDuration:0.35f
                         animations:^{
                             self.enabledView.alpha = 1.0f;
                         }];
    } else {
        [UIView animateWithDuration:0.35f
                         animations:^{
                             self.enabledView.alpha = 0.0f;
                         }];
    }
}




#pragma mark - Motion Manager

- (void)updateMotion {
    _deviceMotion = [self.motionManager deviceMotion];
    
    
}


#pragma mark - Location Manager Delegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    double speed = loc.speed;
    
    if (speed <= 1) {
        if (_stoppedUpdateCount < 0) {
            _stoppedUpdateCount = 0;
        }
    } else {
        _stoppedUpdateCount = -1;
    }
    
    if (speed > 0) {
        self.speedLabel.text = [NSString stringWithFormat:@"Speed: %.02f", speed * 2.237414f /*   m/s to MPH    */];
        self.navigationController.title = self.speedLabel.text;
    } else {
        self.speedLabel.text = @"";
        self.navigationController.title = @"Don't Die While Driving";
    }
    
}



# pragma mark - Gimbal Place Manager Delegate methods'
- (void)placeManager:(GMBLPlaceManager *)manager didBeginVisit:(GMBLVisit *)visit {
    NSLog(@"Begin %@", [visit.place description]);
    [self.placeEvents insertObject:visit
                           atIndex:0];
    _driveModeEnabled = YES;
}

- (void)placeManager:(GMBLPlaceManager *)manager didEndVisit:(GMBLVisit *)visit {
    NSLog(@"End %@", [visit.place description]);
    [self.placeEvents insertObject:visit
                           atIndex:0];
    _driveModeEnabled = NO;
}

@end
