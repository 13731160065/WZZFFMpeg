//
//  WZZFFManager.m
//  WZZFFMpeg
//
//  Created by 王泽众 on 16/8/15.
//  Copyright © 2016年 wzz. All rights reserved.
//

#import "WZZFFManager.h"
#import <CoreGraphics/CoreGraphics.h>

@import ImageIO;
@import MediaPlayer;

#define TEST 1

@interface WZZFFManager ()

@end

#pragma mark - 单例
@implementation WZZFFManager

static WZZFFManager *_instance;

+ (id)allocWithZone:(struct _NSZone *)zone
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [super allocWithZone:zone];
        av_register_all();//注册所有的文件格式和编解码器的库
    });
   
    return _instance;
}

+ (instancetype)sharedWZZFFManager
{
    if (_instance == nil) {
        _instance = [[WZZFFManager alloc] init];
    }
   
    return _instance;
}

#pragma mark - getset方法
- (void)setOutWidth:(double)outWidth {
    if (_outWidth != outWidth) {
        _outWidth = outWidth;
    }
    [self changeSws];
}

- (void)setOutHeight:(double)outHeight {
    if (_outHeight != outHeight) {
        _outHeight = outHeight;
    }
    [self changeSws];
}

- (int64_t)totalTime {
   return pAllFormatContext->duration/AV_TIME_BASE;
}

- (int64_t)totalFrame {
    return pAllFormatContext->streams[allVideoIndex]->nb_frames;
}

- (UIImage *)currentFrameImage {
    //转换图像为RGB24
    sws_scale(pAllSwsContext, pAllFrame->data, pAllFrame->linesize, 0, pAllCodeContext->height, allPic.data, allPic.linesize);
    return [self imageFromAVPicture:allPic width:_outWidth height:_outHeight];
}

#pragma mark - 拆分功能
//获取ffmpeg信息
- (void)getFFInfo {
    printf("\n%s\n", avcodec_configuration());
}

//初始化视频
- (FFERROR)setupVideoWithUrl:(NSString *)url {
    _inUrl = url;
    _startTimeSec = -1;
    
    //释放所有流
    avformat_free_context(pAllFormatContext);
    
    //注册所有流
    av_register_all();
    
    //如果用到网络请求需要注册网络请求
    avformat_network_init();
    
    //打开视频文件
    int openFlag = avformat_open_input(&pAllFormatContext, [url UTF8String], NULL, NULL);
    if (openFlag != 0) {
        NSLog(@"打开视频文件失败");
        return FFERROR_FileOpenFailed;
    }
    
    //查找文件流信息
    int streamFlag = avformat_find_stream_info(pAllFormatContext, NULL);
    if (streamFlag < 0) {
        NSLog(@"查找流信息失败");
        return FFERROR_StreamNotFound;
    }
    
    //查找音频流
    int adAudioIndex = -1;
    adAudioIndex = av_find_best_stream(pAllFormatContext, AVMEDIA_TYPE_AUDIO, -1, 01, &pAllCodec, 0);
    if (adAudioIndex < 0) {
        NSLog(@"在输入流中无法找到音频流");
        return FFERROR_VideoStreamNotFound;
    }
    
    //找到视频流
    allVideoIndex = -1;
    allVideoIndex = av_find_best_stream(pAllFormatContext, AVMEDIA_TYPE_VIDEO, -1, 01, &pAllCodec, 0);
    if (allVideoIndex < 0) {
        NSLog(@"在输入流中无法找到视频流");
        return FFERROR_VideoStreamNotFound;
    }
    
    NSLog(@">>>>>>>>>>>>>音频:%d, 视频:%d", adAudioIndex, allVideoIndex);
    
    //找到解码器
    pAllCodeContext = pAllFormatContext->streams[allVideoIndex]->codec;
    if (pAllCodeContext == NULL) {
        NSLog(@"未找到视频流解码器上下文");
        return FFERROR_CodeContextNotFound;
    }
    
    AVCodecContext * adAllAudioCodeContext;
    adAllAudioCodeContext = pAllFormatContext->streams[adAudioIndex]->codec;
    if (adAllAudioCodeContext == NULL) {
        NSLog(@"未找到音频流解码器上下文");
        return FFERROR_CodeContextNotFound;
    }
    
    AVCodec * adAllAudioCodec = avcodec_find_decoder(adAllAudioCodeContext->codec_id);
    pAllCodec = avcodec_find_decoder(pAllCodeContext->codec_id);
    
    //打开解码器
    int openCodecFlag = avcodec_open2(pAllCodeContext, pAllCodec, NULL);
    if (openCodecFlag != 0) {
        NSLog(@"打开解码器失败");
        return FFERROR_CodecOpenFailed;
    }
    
    //通知解码器，我们能处理截断的bit流
    if (adAllAudioCodec->capabilities&CODEC_CAP_TRUNCATED)
    {
        adAllAudioCodeContext->flags|=CODEC_FLAG_TRUNCATED;
    }
    //打开音频解码器
    if(avcodec_open2(adAllAudioCodeContext, adAllAudioCodec, NULL) < 0)
    {
        return -1;
    }
    
    //设置默认输入输出宽高
    _inWidth = (double)pAllCodeContext->width;
    _inHeight = (double)pAllCodeContext->height;
    if (!_outWidth) {
        _outWidth = _inWidth;
    }
    if (!_outHeight) {
        _outHeight = _inHeight;
    }
    
    //给frame开辟内存
    pAllFrame = av_frame_alloc();
    
    
    
    return FFERROR_OK;
}

//根据这个秒寻找最近的关键帧
- (void)setStartTime:(double)seconds {
    [self seekTime:seconds pFromateContext:pAllFormatContext videoStreamIndex:allVideoIndex pCodecContext:pAllCodeContext];
}

//根据这个秒寻找最近的关键帧
- (void)seekTime:(double)seconds pFromateContext:(AVFormatContext *)pFormatCtx videoStreamIndex:(int)videoStream pCodecContext:(AVCodecContext *)pCodecCtx {
    _startTimeSec = seconds;
    AVRational timeBase = pFormatCtx->streams[videoStream]->time_base;
    int64_t targetFrame = (int64_t)((double)timeBase.den / timeBase.num * seconds);
    avformat_seek_file(pFormatCtx, videoStream, targetFrame, targetFrame, targetFrame, AVSEEK_FLAG_FRAME);
    avcodec_flush_buffers(pCodecCtx);
}

- (BOOL)nextFrame {
    return [self stepFrame:allPacket pFCtx:pAllFormatContext index:allVideoIndex pcode:pAllCodeContext pFrame:pAllFrame];
}

//读取视频流的下一帧.如果没有读到下一帧返回NO(视频结束)
-(BOOL)stepFrame:(AVPacket)packet pFCtx:(AVFormatContext *)pFormatCtx index:(int)videoStream pcode:(AVCodecContext *)pCodecCtx pFrame:(AVFrame *)pFrame {
    if (_startTimeSec == -1) {
        [self setStartTime:0];
    }
    
    // 信息包(AVPacket packet);
    int frameFinished=0;
    
    while(!frameFinished && av_read_frame(pFormatCtx, &packet)>=0) {
        // 判断这个数据包是不是来自视频流(Is this a packet from the video stream?)
        if(packet.stream_index==videoStream) {
            // 解码视频帧
            avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet);
        } else if (packet.stream_index == 0) {
            //解码音频帧
            avcodec_decode_audio4(pCodecCtx, pFrame, &frameFinished, &packet);
        }
    }
    return frameFinished!=0;
}

//改变形变器属性
- (void)changeSws {
    //将久的形变器释放，创建新的形变器，并给新的赋上新值。
    // 释放旧的图片和缩放器(scaler)
    avpicture_free(&allPic);
    sws_freeContext(pAllSwsContext);
    
    //给图片分配内存（RGB格式）
    avpicture_alloc(&allPic, AV_PIX_FMT_RGB24, _outWidth, _outHeight);
    
    //获取视频sws
    pAllSwsContext = sws_getContext(_inWidth,
                                    _inHeight,
                                    pAllCodeContext->pix_fmt,
                                    _outWidth,
                                    _outHeight,
                                    AV_PIX_FMT_RGB24,
                                    SWS_FAST_BILINEAR,
                                    NULL, NULL, NULL);
}

//将yuv格式图像保存为pgm
void pgm_save(unsigned char *buf,int wrap, int xsize,int ysize,char *filename)
{
    FILE *f;
    int i;
    
    //打开文件
    f=fopen(filename,"ab+");
    
    //循环写入
    for(i=0;i<ysize;i++)
    {
        fwrite(buf + i * wrap, 1, xsize, f );
    }
    
    //关闭文件
    fclose(f);
}

//从AVPicture中获取图片
-(UIImage *)imageFromAVPicture:(AVPicture)pict width:(int)width height:(int)height {
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, pict.data[0], pict.linesize[0]*height,kCFAllocatorNull);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate(width,
                                       height,
                                       8,
                                       24,
                                       pict.linesize[0],
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       NO,
                                       kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    CGDataProviderRelease(provider);
    CFRelease(data);
    
    return image;
}

//打印视频信息
- (void)printVideoInfo {
    //dump只是个调试函数，输出文件的音、视频流的基本信息了，帧率、分辨率、音频采样等等
    printf("\n###################################\n");
    printf("#             视频流信息            #\n");
    printf("###################################\n");
    av_dump_format(pAllFormatContext, 0, [_inUrl UTF8String], 0);
    printf("###################################\n");
}

#pragma mark - 成套的功能
//雷笑话转换视频为yuv
- (void)readVideo {
    AVFormatContext *pFormatCtx;
    int             i, videoindex;
    AVCodecContext  *pCodecCtx;
    AVCodec         *pCodec;
    AVFrame *pFrame,*pFrameYUV;
    uint8_t *out_buffer;
    AVPacket *packet;
    int y_size;
    int ret, got_picture;
    struct SwsContext *img_convert_ctx;
    FILE *fp_yuv;
    int frame_cnt;
    clock_t time_start, time_finish;
    double  time_duration = 0.0;
    
    char input_str_full[500]={0};
    char output_str_full[500]={0};
    char info[1000]={0};
    
#if 0
    //输入流路径
    NSString *input_str= [NSString stringWithFormat:@"%@",[[NSBundle mainBundle] pathForResource:@"job" ofType:@"mp4"]];
#endif
    //输入流路径
    NSString *input_str= [NSString stringWithFormat:@"%@",[[NSBundle mainBundle] pathForResource:@"复仇者联盟2" ofType:@"mp4"]];
    
    //输出流路径
    NSString *output_str= [NSHomeDirectory() stringByAppendingString:@"/jppb.yuv"];
    
#if 0
    NSString *input_nsstr=[[[NSBundle mainBundle]resourcePath] stringByAppendingPathComponent:input_str];
    NSString *output_nsstr=[[[NSBundle mainBundle]resourcePath] stringByAppendingPathComponent:output_str];
    
    sprintf(input_str_full,"%s",[input_nsstr UTF8String]);
    sprintf(output_str_full,"%s",[output_nsstr UTF8String]);
#else
    //将输入输出流路径转化为c字符串
    sprintf(input_str_full,"%s",[input_str UTF8String]);
    sprintf(output_str_full,"%s",[output_str UTF8String]);
#endif
    
    //打印输入输出流
    printf("输入流:%s\n",input_str_full);
    printf("输出流:%s\n",output_str_full);
    
    //注册所有
    av_register_all();
    
    //需要播放网络视频时初始化网络
    avformat_network_init();
    
    pFormatCtx = avformat_alloc_context();
    
    if(avformat_open_input(&pFormatCtx,input_str_full,NULL,NULL)!=0){
        printf("无法打开输入流.\n");
        return ;
    }
    if(avformat_find_stream_info(pFormatCtx,NULL)<0){
        printf("不能找到流信息.\n");
        return;
    }
    videoindex=-1;
    for(i=0; i<pFormatCtx->nb_streams; i++)
        if(pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO){
            videoindex=i;
            break;
        }
    
    if(videoindex==-1){
        printf("无法找到视频流.\n");
        return;
    }
    pCodecCtx=pFormatCtx->streams[videoindex]->codec;
    pCodec=avcodec_find_decoder(pCodecCtx->codec_id);
    if(pCodec==NULL){
        printf("无法找到编码器.\n");
        return;
    }
    if(avcodec_open2(pCodecCtx, pCodec,NULL)<0){
        printf("无法打开编码器.\n");
        return;
    }
    
    pFrame=av_frame_alloc();
    pFrameYUV=av_frame_alloc();
    out_buffer=(unsigned char *)av_malloc(av_image_get_buffer_size(AV_PIX_FMT_YUV420P,  pCodecCtx->width, pCodecCtx->height,1));
    av_image_fill_arrays(pFrameYUV->data, pFrameYUV->linesize,out_buffer,
                         AV_PIX_FMT_YUV420P,pCodecCtx->width, pCodecCtx->height,1);
    packet=(AVPacket *)av_malloc(sizeof(AVPacket));
    
    img_convert_ctx = sws_getContext(pCodecCtx->width, pCodecCtx->height, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height, AV_PIX_FMT_YUV420P, SWS_BICUBIC, NULL, NULL, NULL);
    
    
    sprintf(info,   "[Input     ]%s\n", [input_str UTF8String]);
    sprintf(info, "%s[Output    ]%s\n",info,[output_str UTF8String]);
    sprintf(info, "%s[Format    ]%s\n",info, pFormatCtx->iformat->name);
    sprintf(info, "%s[Codec     ]%s\n",info, pCodecCtx->codec->name);
    sprintf(info, "%s[Resolution]%dx%d\n",info, pCodecCtx->width,pCodecCtx->height);
    
    
    fp_yuv=fopen(output_str_full,"wb+");
    if(fp_yuv==NULL){
        printf("无法打开输出文件\n");
        return;
    }
    
    frame_cnt=0;
    time_start = clock();
    
    while(av_read_frame(pFormatCtx, packet)>=0){
        if(packet->stream_index==videoindex){
            ret = avcodec_decode_video2(pCodecCtx, pFrame, &got_picture, packet);
            if(ret < 0){
                printf("Decode Error.\n");
                return;
            }
            if(got_picture){
                sws_scale(img_convert_ctx, (const uint8_t* const*)pFrame->data, pFrame->linesize, 0, pCodecCtx->height, pFrameYUV->data, pFrameYUV->linesize);
                
                y_size=pCodecCtx->width*pCodecCtx->height;
                fwrite(pFrameYUV->data[0],1,y_size,fp_yuv);    //Y
                fwrite(pFrameYUV->data[1],1,y_size/4,fp_yuv);  //U
                fwrite(pFrameYUV->data[2],1,y_size/4,fp_yuv);  //V
                //Output info
                char pictype_str[10]={0};
                switch(pFrame->pict_type){
                    case AV_PICTURE_TYPE_I:sprintf(pictype_str,"I");break;
                    case AV_PICTURE_TYPE_P:sprintf(pictype_str,"P");break;
                    case AV_PICTURE_TYPE_B:sprintf(pictype_str,"B");break;
                    default:sprintf(pictype_str,"Other");break;
                }
                
                printf("Frame Index: %5d. Type:%s\n",frame_cnt,pictype_str);
                frame_cnt++;
            }
        }
        av_free_packet(packet);
        //        av_packet_free(&packet);
    }
    //flush decoder
    //FIX: Flush Frames remained in Codec
    while (1) {
        ret = avcodec_decode_video2(pCodecCtx, pFrame, &got_picture, packet);
        if (ret < 0)
            break;
        if (!got_picture)
            break;
        sws_scale(img_convert_ctx, (const uint8_t* const*)pFrame->data, pFrame->linesize, 0, pCodecCtx->height,
                  pFrameYUV->data, pFrameYUV->linesize);
        int y_size=pCodecCtx->width*pCodecCtx->height;
        fwrite(pFrameYUV->data[0],1,y_size,fp_yuv);    //Y
        fwrite(pFrameYUV->data[1],1,y_size/4,fp_yuv);  //U
        fwrite(pFrameYUV->data[2],1,y_size/4,fp_yuv);  //V
        //Output info
        char pictype_str[10]={0};
        switch(pFrame->pict_type){
            case AV_PICTURE_TYPE_I:sprintf(pictype_str,"I");break;
            case AV_PICTURE_TYPE_P:sprintf(pictype_str,"P");break;
            case AV_PICTURE_TYPE_B:sprintf(pictype_str,"B");break;
            default:sprintf(pictype_str,"Other");break;
        }
        printf("Frame Index: %5d. Type:%s\n",frame_cnt,pictype_str);
        frame_cnt++;
    }
    time_finish = clock();
    time_duration=(double)(time_finish - time_start);
    
    sprintf(info, "%s[Time      ]%fus\n",info,time_duration);
    sprintf(info, "%s[Count     ]%d\n",info,frame_cnt);
    
    sws_freeContext(img_convert_ctx);
    
    fclose(fp_yuv);
    
    av_frame_free(&pFrameYUV);
    av_frame_free(&pFrame);
    avcodec_close(pCodecCtx);
    avformat_close_input(&pFormatCtx);
    
    NSString * info_ns = [NSString stringWithFormat:@"\ninfo:\n%s", info];
    NSLog(@"%@", info_ns);
}

//播放视频
- (void)playVideo:(void (^)(UIImage *))block {
    
    //数据流操作指针
    AVFormatContext * pstream;
    
    //注册全部
    av_register_all();
    
    //如果用到网络请求需要注册网络请求
    avformat_network_init();
    
#if 0
    //输入路径
    NSString *input_str = [NSString stringWithFormat:@"%@",[[NSBundle mainBundle] pathForResource:@"job" ofType:@"mp4"]];
#else
    
    //复仇者联盟2
    NSString *input_str = [NSString stringWithFormat:@"%@",[[NSBundle mainBundle] pathForResource:@"复仇者联盟2" ofType:@"mp4"]];
//    NSString * input_str = @"http://61.182.14.250:38080/sophie.mov";
//    NSString * input_str = [NSString stringWithFormat:@"%@",[[NSBundle mainBundle] pathForResource:@"sophie" ofType:@"mov"]];
#endif
    
#warning 删了下面这句话就崩，不信试试
    char chabbbbbbbb[500];
    
//    sprintf(cha, "%s", [input_str UTF8String]);
//    avformat_open_input(&pstream, cha, NULL, NULL);
    //打开视频文件
    if (avformat_open_input(&pstream, [input_str UTF8String], NULL, NULL) != 0) {
        NSLog(@"打开流失败");
        return;
    }
    
    //查找文件流信息
    if (avformat_find_stream_info(pstream, NULL)) {
        NSLog(@"查找文件流信息失败");
        return;
    }
    
    //dump只是个调试函数，输出文件的音、视频流的基本信息了，帧率、分辨率、音频采样等等
    printf("\n###################################\n");
    printf("#             视频流信息            #\n");
    printf("###################################\n");
    av_dump_format(pstream, 0, [input_str UTF8String], 0);
    printf("###################################\n");
    
    //视频流文件的第一个视频流
    int videoIndex = -1;
    
//    //循环遍历视频流文件的每个流，streams是一个包含流的数组，nb_streams是流数组的总数
//    for (int i = 0; i < pstream->nb_streams; i++) {
//        //找到第一个是视频流的流，codec是视频解码器的指针，codec_type是解码器的类型
//        if (pstream->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO) {
//            videoIndex = i;
//        }
//    }
    AVCodec * codec;
    videoIndex = av_find_best_stream(pstream, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (videoIndex < 0) {
        NSLog(@"在输入文件中无法找到视频流");
        return;
    }
    
    //如果index为默认值说明没找到
//    if (videoIndex == -1) {
//        NSLog(@"未能找到视频流");
//    }
    
    //获取第一个视频流的解码器指针，在编码库中找到该格式的编码器
    AVCodecContext * pcode = pstream->streams[videoIndex]->codec;
    
    codec = avcodec_find_decoder(pcode->codec_id);
    if (codec == NULL) {
        NSLog(@"无法找到编码器");
        return;
    }
    
    //打开解码器
    if (avcodec_open2(pcode, codec, NULL)) {
        NSLog(@"无法打开编码器");
        return;
    }
    
    //给frame开辟内存
    AVFrame * pframe = av_frame_alloc();
    
    //输出宽高
    int outW = (int)[UIScreen mainScreen].bounds.size.width;
    int outH = [UIScreen mainScreen].bounds.size.width/pcode->width*pcode->height;
    
    //创建图片
    AVPicture pic;
    avpicture_alloc(&pic, AV_PIX_FMT_RGB24, outW, outH);
    
    //获取视频sws
    struct SwsContext * img_convert_ctx = sws_getContext(pcode->width,
                                     pcode->height,
                                     pcode->pix_fmt,
                                     outW,
                                     outH,
                                     AV_PIX_FMT_RGB24,
                                     SWS_FAST_BILINEAR,
                                     NULL, NULL, NULL);
    NSLog(@"%lld", pstream->duration/AV_TIME_BASE);
    //设置到0秒时的关键帧
//    [self seekTime:fff pFromateContext:pstream videoStreamIndex:videoIndex pCodecContext:pcode];
    
    dispatch_queue_t ttt = dispatch_queue_create("aaa", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(ttt, ^{
        int fff = 0;
#if 1
        AVRational timeBase = pstream->streams[videoIndex]->time_base;
        int64_t targetFrame = (int64_t)((double)timeBase.den / timeBase.num * fff);
        avformat_seek_file(pstream, videoIndex, targetFrame, targetFrame, targetFrame, AVSEEK_FLAG_FRAME);
        avcodec_flush_buffers(pcode);
#endif
        for (; ; ) {

            
            AVPacket packet;
            if (![self stepFrame:packet pFCtx:pstream index:videoIndex pcode:pcode pFrame:pframe]) {
                NSLog(@"到结尾:%d", fff);
                return;
            }
            
            //转换图像为RGB24
            sws_scale(img_convert_ctx, pframe->data, pframe->linesize, 0, pcode->height, pic.data, pic.linesize);
            
            UIImage * img = [self imageFromAVPicture:pic width:outW height:outH];
            if (block) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    block(img);
                });
            }
            
            [NSThread sleepForTimeInterval:1.0/30];
            fff++;
        }
    });
    
#if 0
    
    //创建帧指针，指向解码后的原始帧
    AVFrame * pframe = av_frame_alloc();
    AVFrame * pYUVFrame = av_frame_alloc();
    
    //给FrameYUV帧分配内存
    uint8_t * out_buffer = (unsigned char *)av_malloc(av_image_get_buffer_size(AV_PIX_FMT_YUV420P, pcode->width, pcode->height, 1));
    av_image_fill_arrays(pframe->data, pframe->linesize, out_buffer, AV_PIX_FMT_YUV420P, pcode->width, pcode->height, 1);
    
    //还不知道是什么东西
    AVPacket * packet=(AVPacket *)av_malloc(sizeof(AVPacket));
    
    //生成sws操作指针，参数1.源视频宽，2.源视频高，3.源视频格式，4.目的视频宽，5.目的视频高，6.目的视频格式，7.标记指定的算法和缩放，8.9.10.调整视频的参数（未知），返回sws指针，如果失败返回NULL
    /*
     sws_getContext 函数可以看做是初始化函数，它的参数定义分别为：
     int srcW，int srcH 为原始图像数据的高和宽；
     int dstW，int dstH 为输出图像数据的高和宽；
     enum AVPixelFormat srcFormat 为输入和输出图片数据的类型；eg：AV_PIX_FMT_YUV420、PAV_PIX_FMT_RGB24；
     int flags 为scale算法种类；eg：SWS_BICUBIC、SWS_BICUBLIN、SWS_POINT、SWS_SINC；
     SwsFilter *srcFilter ，SwsFilter *dstFilter，const double *param 可以不用管，全为NULL即可；
     */
    
    struct SwsContext * img_convert_ctx = sws_getContext(pcode->width, pcode->height, pcode->pix_fmt, pcode->width, pcode->height, AV_PIX_FMT_YUV420P, SWS_BICUBIC, NULL, NULL, NULL);
    if (img_convert_ctx == NULL) {
        NSLog(@"sws指针获取失败");
        return;
    }
    
    /*
     sws_scale 函数则为执行函数，它的参数定义分别为：
     struct SwsContext *c 为sws_getContext函数返回的值；
     const uint8_t *const srcSlice[]，uint8_t *const dst[] 为输入输出图像数据各颜色通道的buffer指针数组；
     const int srcStride[]，const int dstStride[] 为输入输出图像数据各颜色通道每行存储的字节数数组；
     int srcSliceY 为从输入图像数据的第多少列开始逐行扫描，通常设为0；
     int srcSliceH 为需要扫描多少行，通常为输入图像数据的高度；
     */
    ScaleImg(pcode, pframe, pYUVFrame, pcode->height, pcode->width);
    
    
    pgm_save(pYUVFrame->data[0], pYUVFrame->linesize[0], //Y
             pcode->width, pcode->height, "fff.yuv");
    pgm_save(pYUVFrame->data[1], pYUVFrame->linesize[1],
             pcode->width/2, pcode->height/2, "fff.yuv"); //U
    pgm_save(pYUVFrame->data[2], pYUVFrame->linesize[2],
             pcode->width/2, pcode->height/2, "fff.yuv");  //V
#endif

}

@end

