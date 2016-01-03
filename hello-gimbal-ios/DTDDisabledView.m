//
//  DTDDisabledView.m
//  Don't Die
//
//  Created by HAI on 1/3/16.
//  Copyright © 2016 Nathan Fennel. All rights reserved.
//

#import "DTDDisabledView.h"

@implementation DTDDisabledView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.82f
                                               green:0.0f
                                                blue:0.0f
                                               alpha:1.0f];
        self.titleLabel.text = @"Drive Mode Disabled";
        
        self.titleLabel.font = [UIFont systemFontOfSize:24.0f];
        
        CGRect titleLabelFrame = self.titleLabel.frame;
        titleLabelFrame.size.height = 66.0f;
        self.titleLabel.frame = titleLabelFrame;
        
        [self addSubview:self.dataRewardLabel];
    }
    
    return self;
}

- (UILabel *)dataRewardLabel {
    if (!_dataRewardLabel) {
        _dataRewardLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0f,
                                                                     0.0f,
                                                                     self.frame.size.width,
                                                                     100.0f)];
        _dataRewardLabel.center = self.center;
        _dataRewardLabel.font = [UIFont systemFontOfSize:24.0f];
        _dataRewardLabel.textAlignment = NSTextAlignmentCenter;
        _dataRewardLabel.textColor = [UIColor whiteColor];
        _dataRewardLabel.numberOfLines = 0;
    }
    
    return _dataRewardLabel;
}

@end
