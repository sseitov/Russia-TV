//
//  TVController.mm
//  Russia TV
//
//  Created by Sergey Seitov on 13.10.14.
//  Copyright (c) 2014 Sergey Seitov. All rights reserved.
//

#import "TVController.h"
#import "MBProgressHUD.h"

static NSString* mediaURL[4] = {
    @"http://panels.telemarker.cc/stream/ort-tm.ts",
    @"http://panels.telemarker.cc/stream/rtr-tm.ts",
    @"http://panels.telemarker.cc/stream/tvc-tm.ts",
    @"http://panels.telemarker.cc/stream/ntv-tm.ts"
};

@interface TVController ()

@property (strong, nonatomic) IBOutlet UISegmentedControl *channels;

@end

@implementation TVController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _channels = [[UISegmentedControl alloc] initWithItems:@[@"ОРТ",@"РТР",@"ТВЦ",@"НТВ"]];
    [_channels setImage:[UIImage imageNamed:@"ort"] forSegmentAtIndex:0];
    [_channels setImage:[UIImage imageNamed:@"rtr"] forSegmentAtIndex:1];
    [_channels setImage:[UIImage imageNamed:@"tvc"] forSegmentAtIndex:2];
    [_channels setImage:[UIImage imageNamed:@"ntv"] forSegmentAtIndex:3];
    
    _channels.center = CGPointMake(self.view.center.x, 50);
    [_channels addTarget:self action:@selector(channelChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_channels];
    
    [self performSelector:@selector(hideChannels) withObject:nil afterDelay:1.0];
    
    UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(taspOnScreen:)];
    [[self view] addGestureRecognizer:tap];
    
    _channels.selectedSegmentIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"Channel"];
    [self setChannel:(int)_channels.selectedSegmentIndex];
}

- (void)hideChannels
{
    [self showChannels:NO];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [UIView animateWithDuration:.3 animations:^(){
        CGRect frame = _channels.frame;
        frame.origin.x = (self.view.frame.size.width - frame.size.width)/2;
        _channels.frame = frame;
    }];
}

- (void)showChannels:(BOOL)show
{
    [UIView animateWithDuration:.5 animations:^(){
        CGRect frame = _channels.frame;
        if (show) {
            frame.origin.y = 20;
        } else {
            frame.origin.y = -49.0;
        }
        frame.origin.x = (self.view.frame.size.width - frame.size.width)/2;
        _channels.frame = frame;
    }];
}

- (void)taspOnScreen:(UITapGestureRecognizer*)gesture
{
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self showChannels:(_channels.frame.origin.y <= 0)];
    }
}

- (IBAction)channelChanged:(UISegmentedControl *)sender
{
    [[NSUserDefaults standardUserDefaults] setInteger:sender.selectedSegmentIndex forKey:@"Channel"];
    [self setChannel:(int)sender.selectedSegmentIndex];
    [self showChannels:NO];
}

- (void)setChannel:(int)channel
{
}

- (void)errorOpen
{
    [MBProgressHUD hideHUDForView:self.view animated:YES];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                    message:@"Error open TV channel"
                                                   delegate:nil
                                          cancelButtonTitle:@"Ok"
                                          otherButtonTitles:nil];
    [alert show];
}

@end
