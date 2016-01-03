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
        
        [self.titleLabel sizeToFit];
    }
    
    return self;
}

@end
