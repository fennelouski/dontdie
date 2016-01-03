//
//  DTDEnabledView.m
//  Don't Die
//
//  Created by HAI on 1/3/16.
//  Copyright © 2016 Nathan Fennel. All rights reserved.
//

#import "DTDEnabledView.h"

@interface DTDEnabledView ()

@property (nonatomic, strong) UILabel *warningLabel;

@end

@implementation DTDEnabledView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.0f
                                               green:0.388f
                                                blue:0.0f
                                               alpha:1.0f];
        self.titleLabel.text = @"Drive Mode Enabled";
        
        [self addSubview:self.warningLabel];
    }
    
    return self;
}

- (UILabel *)warningLabel {
    if (!_warningLabel) {
        _warningLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0f,
                                                                  self.frame.size.height - 100.0f,
                                                                  self.frame.size.width,
                                                                  100.0f)];
        _warningLabel.textAlignment = NSTextAlignmentCenter;
        _warningLabel.textColor = [UIColor whiteColor];
        _warningLabel.font = [UIFont systemFontOfSize:24.0f];
        _warningLabel.text = @"Phone calls and texts will be postponed until the vehicle is stopped.";
        _warningLabel.numberOfLines = 0;
    }
    
    return _warningLabel;
}

@end
