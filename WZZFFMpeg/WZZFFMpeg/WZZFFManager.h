//
//  WZZFFManager.h
//  WZZFFMpeg
//
//  Created by 王泽众 on 16/8/15.
//  Copyright © 2016年 wzz. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "avformat.h"
#import "avio.h"
#import "avcodec.h"
#import "imgutils.h"
#import "swscale.h"

typedef enum {
    FFERROR_OK,
    FFERROR_FileOpenFailed,
    FFERROR_StreamNotFound,
    FFERROR_VideoStreamNotFound,
    FFERROR_CodeContextNotFound,
    FFERROR_CodecOpenFailed
}FFERROR;

@interface WZZFFManager : NSObject
{
    @public//方便外部调用，但一般不建议使用
    //全局流
    AVFormatContext * pAllFormatContext;
    
    //全局解码器
    AVCodec * pAllCodec;
    
    //全局解码器上下文
    AVCodecContext * pAllCodeContext;
    
    //视频流位置
    int allVideoIndex;
    
    //输出图像
    AVPicture allPic;
    
    //变形器
    struct SwsContext * pAllSwsContext;
    
    //数据包
    AVPacket allPacket;
    
    //帧
    AVFrame * pAllFrame;
}

/**
 输入视频地址，只读
 >在setupVideoWithUrl:方法中设置
 */
@property (copy, nonatomic, readonly) NSString * inUrl;

/**
 输出视频地址
 */
@property (copy, nonatomic) NSString * outUrl;

/**
 输入宽，只读
 */
@property (assign, nonatomic, readonly) double inWidth;

/**
 输入高，只读
 */
@property (assign, nonatomic, readonly) double inHeight;

/**
 输出宽
 */
@property (assign, nonatomic) double outWidth;

/**
 输出高
 */
@property (assign, nonatomic) double outHeight;

/**
 总时间，只读
 */
@property (assign, nonatomic, readonly) int64_t totalTime;

/**
 总帧，只读
 */
@property (assign, nonatomic, readonly) int64_t totalFrame;

/**
 开始时间，只读，－1为默认状态，会设置为0
 */
@property (assign, nonatomic, readonly) double startTimeSec;

/**
 当前帧图片，只读
 */
@property (strong, nonatomic, readonly) UIImage * currentFrameImage;

/**
 获取ffmanager对象
 */
+ (instancetype)sharedWZZFFManager;

/**
 初始化视频
 */
- (FFERROR)setupVideoWithUrl:(NSString *)url;

/**
 根据这个秒寻找最近的关键帧
 */
-(void)setStartTime:(double)seconds;

/**
 下一帧
 */
- (BOOL)nextFrame;

/**
 获取ffmpeg的信息
 */
- (void)getFFInfo;

/**
 打印视频信息
 */
- (void)printVideoInfo;

/**
 保存yuv格式视频
 */
- (void)readVideo;

/**
 播放视频
 */
- (void)playVideo:(void(^)(UIImage * img))block;

@end
