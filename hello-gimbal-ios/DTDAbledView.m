//
//  DTDAbledView.m
//  Don't Die
//
//  Created by HAI on 1/3/16.
//  Copyright © 2016 Nathan Fennel. All rights reserved.
//

#import "DTDAbledView.h"

@implementation DTDAbledView {
    UILabel *_titleLabel;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        [self addSubview:self.titleLabel];
    }
    
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    [self addSubview:self.titleLabel];
    self.titleLabel.frame = CGRectMake(0.0f,
                                       60.0f,
                                       self.bounds.size.width,
                                       self.bounds.size.height * 0.6f);
}

- (UILabel *)titleLabel {
    if (!_titleLabel) {
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0f,
                                                                60.0f,
                                                                self.bounds.size.width,
                                                                self.bounds.size.height * 0.6f)];
        _titleLabel.font = [UIFont boldSystemFontOfSize:72.0f];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.numberOfLines = 0;
        _titleLabel.text = @"QWEROIUQ WELRKJQ WEPFOJQWE QPWEOJV: Q\n\nQWEIRUJQ WILJQV<QNWE VLI\n\nQWIEFH Q<JVkhjqwluwqhjkvqwhjk.";
    }
    
    return _titleLabel;
}

- (void)setTitleLabel:(UILabel *)titleLabel {
    _titleLabel = titleLabel;
}

@end
