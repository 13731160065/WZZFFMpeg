//
//  ViewController.m
//  WZZFFMpeg
//
//  Created by 王泽众 on 16/8/11.
//  Copyright © 2016年 wzz. All rights reserved.
//

#import "ViewController.h"
#import "WZZFFManager.h"

@interface ViewController ()<UITableViewDelegate, UITableViewDataSource>
{
    NSMutableArray * dataArr;
    NSTimer * timerrrr;
}
@property (weak, nonatomic) IBOutlet UITableView *mainTableView;
@property (weak, nonatomic) IBOutlet UIImageView *mainImageView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [_mainTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [self loadData];
}

- (void)loadData {
    dataArr = [NSMutableArray arrayWithArray:@[@"获取用户信息", @"读取视频信息", @"播放视频", @"播放视频"]];
    [_mainTableView reloadData];
}

#pragma mark - tableview代理
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return dataArr.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    
    [[cell textLabel] setText:dataArr[indexPath.row]];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch (indexPath.row) {
        case 0:
        {
            [[WZZFFManager sharedWZZFFManager] getFFInfo];
        }
            break;
        case 1:
        {
            [[WZZFFManager sharedWZZFFManager] readVideo];
        }
            break;
        case 2:
        {
            [[WZZFFManager sharedWZZFFManager] playVideo:^(UIImage *img) {
                    [_mainImageView setImage:img];
            }];
        }
        case 3:
        {
            WZZFFManager * man = [WZZFFManager sharedWZZFFManager];
            [man setupVideoWithUrl:[[NSBundle mainBundle] pathForResource:@"复仇者联盟2" ofType:@"mp4"]];
            man.outWidth = [UIScreen mainScreen].bounds.size.width;
            man.outHeight = man.outWidth/man.inWidth*man.inHeight;
            [man setStartTime:0.0f];
            timerrrr = [NSTimer scheduledTimerWithTimeInterval:1.0f/30.0f target:self selector:@selector(timerRun) userInfo:nil repeats:YES];
        }
            break;
            
        default:
            break;
    }
}

- (void)timerRun {
    WZZFFManager * man = [WZZFFManager sharedWZZFFManager];
    [man nextFrame];
    [_mainImageView setImage:man.currentFrameImage];
}

@end
