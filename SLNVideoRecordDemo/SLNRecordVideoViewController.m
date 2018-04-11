//
//  SLNRecordVideoViewController.m
//  SLNVideoRecordDemo
//
//  Created by 乔冬 on 17/3/23.
//  Copyright © 2017年 XinHuaTV. All rights reserved.
//

#import "SLNRecordVideoViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import "SLNConvertedToFormatTool.h"
typedef enum {
    SLNCameraModeVideo = 0,
     SLNCameraModeTakePicture ,
    SLNCameraModeAudioRecord ,
    
}SLNCameraMode;
#define kRecordAudioFile @"myRecord.caf"
typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);
@interface SLNRecordVideoViewController ()<AVCaptureFileOutputRecordingDelegate,AVAudioRecorderDelegate>
{
    //记录闪光灯点击的次数
    NSInteger  clickBtnCount;
    SLNCameraMode slnCameraMode;
}

//负责输入和输出设置之间的数据传递
@property (nonatomic,strong) AVCaptureSession *slnCaptureSession;
//负责从AVCaptureDevice获得输入流
@property (nonatomic,strong) AVCaptureDeviceInput *slnCaptureDeviceInput ;
//视频输出流
@property (nonatomic,strong) AVCaptureMovieFileOutput *slnCaptureMovieFileOutput;
////照片输出流
@property (nonatomic,strong) AVCaptureStillImageOutput *slnCaptureStillImageOutput;
//相机拍摄预览层
@property (nonatomic,strong) AVCaptureVideoPreviewLayer *slnCaptureVideoPreviewLayer;

//是否允许旋转（注意在视频录制过程中禁止屏幕旋转）
@property (assign,nonatomic) BOOL enableRotation;
@property (assign,nonatomic) CGRect *lastBounds;//旋转的前大小
@property (assign,nonatomic) UIBackgroundTaskIdentifier backgroundTaskIdentifier;//后台任务标识
@property (strong, nonatomic) IBOutlet UIView *slnTopContainerView;

@property (weak, nonatomic) IBOutlet UIView *slnContainerView;
//拍照按钮
@property (weak, nonatomic) IBOutlet UIButton *slnTakeButton;
//聚焦光标
@property (weak, nonatomic) IBOutlet UIImageView *slnFocusCursorView;
//时间的设置
@property (weak, nonatomic) IBOutlet UILabel *slnTimeRecordLabel;
//切换前置后置
@property (weak, nonatomic) IBOutlet UIButton *slnToggleBtn;
//设置闪光灯
@property (weak, nonatomic) IBOutlet UIButton *slnFlashButton;


//定时器主要记录时间的显示
@property (nonatomic,strong) NSTimer *slnRecordTimer;
//开始时间
@property (nonatomic,strong) NSDate *beginDate;
//结束的时间
@property (nonatomic,strong) NSDate *endDate;
//录视频和拍照的切换等
@property (strong, nonatomic) IBOutlet UISegmentedControl *slnSegmentedControl;
@property (nonatomic,strong)     UILongPressGestureRecognizer *slnPressRecognizer ;


@property (nonatomic,strong) PHFetchResult<PHAsset *> *createdAssets;
@property (nonatomic,strong)  PHAssetCollection *createdCollection ;
@property (nonatomic,strong) UIImage *slnSavePic;
//录音机
@property (nonatomic,strong)  AVAudioRecorder *audioRecorder;
@end

@implementation SLNRecordVideoViewController
-(void)dealloc{
    [self removeNotification];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // 1.初始化会话层
    _slnCaptureSession = [[AVCaptureSession alloc]init];
    //1.1 设置分辨率
    if ([_slnCaptureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        _slnCaptureSession.sessionPreset = AVCaptureSessionPreset1280x720;
    }
    //2.获得输入设备
    AVCaptureDevice *slnCaptureDevice = [self slnAssignCameraDeviceWithPosition:AVCaptureDevicePositionBack];
    if(!slnCaptureDevice){
        NSLog(@"获取后置摄像头出现问题");
        return;
    }

    
    //3.根据输入设置初始化设备输入对象，来获取输入数据
    NSError *error;
    _slnCaptureDeviceInput = [[AVCaptureDeviceInput alloc]initWithDevice:slnCaptureDevice error:&error];
    if (error) {
        NSLog(@"获取设备输入对象出现问题，错误的原因：%@",        error.localizedDescription);
        return;
    }
    [self setVideoMode:SLNCameraModeVideo];
    
      //8.创建视频预览层，实时展示摄像头的状态
    _slnCaptureVideoPreviewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.slnCaptureSession];
    
    CALayer *slnLayer = self.slnContainerView.layer;
    slnLayer.masksToBounds = YES;
    _slnCaptureVideoPreviewLayer.frame = slnLayer.bounds;
    //设置填充样式
    _slnCaptureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    //将视频预览层添加到界面
//    [slnLayer addSublayer:_slnCaptureVideoPreviewLayer];
    [slnLayer insertSublayer:self.slnCaptureVideoPreviewLayer below:self.slnFocusCursorView.layer];
    _enableRotation = YES;
    [self addNotificationToCaptureDevice:slnCaptureDevice];
    [self addGenstureRecognizer];

    _slnRecordTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(slnRecordAction:) userInfo:nil repeats:YES ];
    
    
    //关闭定时器
    [self slnCannelRecordTimer];
    
    //slnSegmentedControl
    
}
#pragma mark--切换模式
- (IBAction)slnSegmentedControlAction:(UISegmentedControl *)sender {
    NSInteger index = sender.selectedSegmentIndex;
    NSLog(@"%ld",index);
    _slnCaptureVideoPreviewLayer.hidden = NO;
    _slnToggleBtn.hidden = NO;
    _slnFlashButton.hidden = NO;
    if (index == SLNCameraModeVideo) {
        [self setVideoMode:SLNCameraModeVideo];
        slnCameraMode = SLNCameraModeVideo;
    }else if (index == SLNCameraModeTakePicture){
        [self setPcitureMode:SLNCameraModeTakePicture];
                slnCameraMode = SLNCameraModeTakePicture;
    }else if (index == SLNCameraModeAudioRecord){
        _slnToggleBtn.hidden = YES;
        _slnFlashButton.hidden = YES;
        _slnCaptureVideoPreviewLayer.hidden = YES;
        slnCameraMode = SLNCameraModeAudioRecord;
        [self setslnAudioRecorderMode:SLNCameraModeAudioRecord];
    }
}


#pragma mark -- 定时器时间的控制器
-(void)slnRecordAction:(NSTimer *)timer{
    _endDate = timer.fireDate ;
//   float  endBeginTimer =   [_endDate timeIntervalSinceDate:_beginDate];
    if ( [_endDate timeIntervalSince1970]*1 >=0) {
        self.slnTimeRecordLabel.text = [self dateTimeDifferenceWithStartTime:_beginDate endTime:_endDate];
    }
//    _beginDate = timer.fireDate;
    NSLog(@"%@",timer.fireDate);
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [_slnCaptureSession startRunning];
}
-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    [_slnCaptureSession stopRunning];
}
//设置隐藏状态bar
- (BOOL)prefersStatusBarHidden {
    return YES;
}
//设置是否应该旋转
-(BOOL)shouldAutorotate{
    return _enableRotation;
}

//屏幕旋转时调整视频预览图层的方向
-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration{
    AVCaptureConnection *captureConnection = [self.slnCaptureVideoPreviewLayer connection];
    captureConnection.videoOrientation = (AVCaptureVideoOrientation)toInterfaceOrientation;
}
//旋转后重新设置大小
-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation{
    _slnCaptureVideoPreviewLayer.frame = self.slnContainerView.bounds;
}
#pragma mark--方法
#pragma mark--录制视频和拍照片等
- (IBAction)takeButtonClick:(UIButton *)sender {
    [self removeLongPressGenstureRecognizer];

    switch (slnCameraMode) {
        case SLNCameraModeVideo:
        {
            //1.根据设备输出对象获得连接
            AVCaptureConnection *captureConnection = [self.slnCaptureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            //2.根据连接，获取设备输出的数据
            if(![self.slnCaptureMovieFileOutput isRecording ]){
                
                self.enableRotation = NO;
                //如果支持多任务，则开始多任务
                if ([[UIDevice currentDevice] isMultitaskingSupported]) {
                    self.backgroundTaskIdentifier = [[UIApplication sharedApplication]beginBackgroundTaskWithExpirationHandler:nil ];
                }
                //预览图层和视频方向保持一致
                captureConnection.videoOrientation = [self.slnCaptureVideoPreviewLayer connection ].videoOrientation;
                NSString *outputFielPath=[NSTemporaryDirectory() stringByAppendingString:@"myMovie.mov"];
                NSLog(@"save path is :%@",outputFielPath);
                NSURL *fileUrl=[NSURL fileURLWithPath:outputFielPath];
                [self.slnCaptureMovieFileOutput startRecordingToOutputFileURL:fileUrl recordingDelegate:self];
                _beginDate = [NSDate date];
                [self slnbeginRecordTimer];
                
            }else{
                self.slnTimeRecordLabel.text = @"00:00:00";
                [self.slnCaptureMovieFileOutput stopRecording];
                [self slnCannelRecordTimer];
            }
            break;
        }
            
    case SLNCameraModeTakePicture:
        {
            [self addLongPressGenstureRecognizer];
            [self slnSavePicture];
            break;
        }
    case SLNCameraModeAudioRecord:
        {
            if (![self.audioRecorder isRecording]) {
                [self.audioRecorder record];//首次使用应用时如果调用record方法会询问用户是否允许使用麦克风;
                _beginDate = [NSDate date];
                [self slnbeginRecordTimer];
            }else{
                self.slnTimeRecordLabel.text = @"00:00:00";
                [self.audioRecorder stop];
                [self slnCannelRecordTimer];
            }
            break;
        }
    }
    
    [self slnFocusCursorView];
    
}
#pragma mark -- 长按连拍
-(void)slnLongPressGestureRecognizer:(UILongPressGestureRecognizer *)pressRecognizer{

    for (int i =0 ; i < 10; i++) {
              [self slnSavePicture];
        NSLog(@"照片：%d",i);
    }

}
#pragma mark -- 闪光灯设置
- (IBAction)slnFashAction:(UIButton *)sender {
    if (clickBtnCount >2) {
        clickBtnCount = 0;
    }

    NSLog(@"%ld",clickBtnCount);
    NSInteger clikedCount = clickBtnCount;
    NSString *imgString ;
    AVCaptureFlashMode flashMode;
    AVCaptureTorchMode torchMode;
    if (clikedCount == 0) {
        imgString = @"icon_btn_camera_flash_off";
        flashMode = AVCaptureFlashModeOff;
        torchMode = AVCaptureTorchModeOff;
    }else if (clikedCount == 1){
        imgString = @"icon_btn_camera_flash_on";
        flashMode = AVCaptureFlashModeOn;
        torchMode = AVCaptureTorchModeOn;
    }else if (clikedCount == 2){
        imgString = @"icon_btn_camera_flash_auto";
        flashMode = AVCaptureFlashModeAuto;
        torchMode = AVCaptureTorchModeAuto;
    }
//    if (clikedCount == 0) {
//        
//          imgString = @"btn_video_flash_close";
//    }else if (clikedCount == 1){
//          imgString = @"btn_video_flash_open";
//    }else if (clikedCount == 2){
//          imgString = @"icon_btn_camera_flash_auto";
//    }else if (clikedCount == 3){
//          imgString = @"icon_btn_camera_flash_on";
//    }else if (clikedCount == 4){
//          imgString = @"icon_btn_camera_flash_off";
//    }
    clickBtnCount ++;
    //下面的两个方法，必须一块设置
    [self setFlashMode:flashMode];
    [self setTorchMode:torchMode];

    [sender setImage:[UIImage imageNamed:imgString] forState:UIControlStateNormal];
    
}

#pragma mark 切换前后摄像头
- (IBAction)toggleButtonClick:(UIButton *)sender {
    
    AVCaptureDevice *currentDevice = [self.slnCaptureDeviceInput device];
    AVCaptureDevicePosition currentDevicePosition = [currentDevice position];
    [self removeNotificationFromCaptureDevice:currentDevice];
    
    AVCaptureDevice *toChangeDevice ;
    AVCaptureDevicePosition toChangePosition = AVCaptureDevicePositionFront;
    
    if (currentDevicePosition == AVCaptureDevicePositionUnspecified || currentDevicePosition == AVCaptureDevicePositionFront) {
        toChangePosition = AVCaptureDevicePositionBack;
    }
    
    toChangeDevice=[self slnAssignCameraDeviceWithPosition:toChangePosition];
    [self addNotificationToCaptureDevice:toChangeDevice];
    //获得要调整的设备输入对象
    AVCaptureDeviceInput *toChangeDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:toChangeDevice error:nil];
    
    //改变会话的配置前一定要先开启配置，配置完成后提交配置改变
    [self.slnCaptureSession beginConfiguration];
    //移除原有输入对象
    [self.slnCaptureSession removeInput:self.slnCaptureDeviceInput];
    //添加新的输入对象
    if ([self.slnCaptureSession canAddInput:toChangeDeviceInput]) {
        [self.slnCaptureSession addInput:toChangeDeviceInput];
        self.slnCaptureDeviceInput = toChangeDeviceInput;
    }
    //提交会话配置
    [self.slnCaptureSession commitConfiguration];
   
}
#pragma mark -- 代理
#pragma mark -- AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections{
    NSLog(@"开始录制");
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error{
    NSLog(@"完成录制");
    //视频录入完成之后在后台将视频存储到相簿
    self.enableRotation = YES;
    [SLNConvertedToFormatTool slConvertedIntoMP4WithFileUrl:outputFileURL success:^(id response) {
        NSLog(@"%@",response);
    } failure:^(id error) {
        
    }];
    
    UIBackgroundTaskIdentifier lastBackgroundTaskIdentifier = self.backgroundTaskIdentifier;
    self.backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    AVURLAsset *avUrl = [AVURLAsset assetWithURL:outputFileURL];
    CMTime time = [avUrl duration];
    int seconds = ceil(time.value/time.timescale);
    NSLog(@"%d",seconds);
//    self.slnTimeRecordLabel.text = [NSString stringWithFormat:@"%d",seconds];
    ALAssetsLibrary *assetsLibrary = [[ALAssetsLibrary alloc]init];
    [assetsLibrary writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
        
        if (error) {
            NSLog(@"保存视频到相簿过程中发生错误，错误信息：%@",error.localizedDescription);
        }
        if (lastBackgroundTaskIdentifier!=UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:lastBackgroundTaskIdentifier];
        }
        NSLog(@"成功保存视频到相簿.");
        
    }];
    
    
}
#pragma mark - 录音机代理方法
/**
 *  录音完成，录音完成后播放录音
 *
 *  @param recorder 录音机对象
 *  @param flag     是否成功
 */
-(void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag{
    if (flag) {
        NSLog(@"录音完成!");
    }else{
        NSLog(@"录音失败!");
    }
}
- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError * __nullable)error{
      NSLog(@"录音失败!");
}
#pragma mark - 通知
/**
 *  给输入设备添加通知
 */
-(void)addNotificationToCaptureDevice:(AVCaptureDevice *)captureDevice{
    //注意添加区域改变捕获通知必须首先设置设备允许捕获
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        captureDevice.subjectAreaChangeMonitoringEnabled=YES;
    }];
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //捕获区域发生改变
    [notificationCenter addObserver:self selector:@selector(areaChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
-(void)removeNotificationFromCaptureDevice:(AVCaptureDevice *)captureDevice{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
/**
 *  移除所有通知
 */
-(void)removeNotification{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self];
}

-(void)addNotificationToCaptureSession:(AVCaptureSession *)captureSession{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //会话出错
    [notificationCenter addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:captureSession];
}

/**
 *  设备连接成功
 *
 *  @param notification 通知对象
 */
-(void)deviceConnected:(NSNotification *)notification{
    NSLog(@"设备已连接...");
}
/**
 *  设备连接断开
 *
 *  @param notification 通知对象
 */
-(void)deviceDisconnected:(NSNotification *)notification{
    NSLog(@"设备已断开.");
}
/**
 *  捕获区域改变
 *
 *  @param notification 通知对象
 */
-(void)areaChange:(NSNotification *)notification{
    NSLog(@"捕获区域改变...");
}

/**
 *  会话出错
 *
 *  @param notification 通知对象
 */
-(void)sessionRuntimeError:(NSNotification *)notification{
    NSLog(@"会话发生错误.");
}
#pragma mark -- 私有方法
#pragma mark -- 录制视频
-(void)setVideoMode:( SLNCameraMode) slnCameraMode{
        self.slnTimeRecordLabel.hidden = NO;
       [_slnCaptureSession removeOutput:_slnCaptureStillImageOutput];
    //4.添加一个音频输入设备
    AVCaptureDevice *audioCaptureDevice=[[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
      NSError *error;
    AVCaptureDeviceInput *audioCaptureDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:audioCaptureDevice error:&error];
    if (error) {
        NSLog(@"取得设备输入对象时出错，错误原因：%@",error.localizedDescription);
        return;
    }
    //5. 初始化设备输出对象，用于获得输出数据
    _slnCaptureMovieFileOutput = [[AVCaptureMovieFileOutput alloc]init];
    
    //6.将设备输入对象添加到会话层
    if ([_slnCaptureSession canAddInput:_slnCaptureDeviceInput]) {
        [_slnCaptureSession addInput:_slnCaptureDeviceInput];
        [_slnCaptureSession addInput:audioCaptureDeviceInput];
        
        AVCaptureConnection *captureConnection = [_slnCaptureMovieFileOutput  connectionWithMediaType:AVMediaTypeVideo];
        if ([captureConnection isVideoStabilizationSupported]) {//是否支持稳定视频模式
            [captureConnection setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeAuto];
        }
    }
    //7.将设备输出对象添加到会话层
    if ([_slnCaptureSession canAddOutput:_slnCaptureMovieFileOutput]) {
        [_slnCaptureSession addOutput:_slnCaptureMovieFileOutput];
    }
}
#pragma mark -- 拍照
-(void)setPcitureMode:( SLNCameraMode) slnCameraMode{
    self.slnTimeRecordLabel.hidden = YES;
    [_slnCaptureSession removeOutput:_slnCaptureMovieFileOutput];
    //初始化设备输出对象，用于获得输出数据
    _slnCaptureStillImageOutput=[[AVCaptureStillImageOutput alloc]init];
    NSDictionary *outputSettings = @{AVVideoCodecKey:AVVideoCodecJPEG};
    [_slnCaptureStillImageOutput setOutputSettings:outputSettings];//输出设置
    
    //将设备输入添加到会话中
    if ([_slnCaptureSession canAddInput:_slnCaptureDeviceInput]) {
        [_slnCaptureSession addInput:_slnCaptureDeviceInput];
    }
    
    //将设备输出添加到会话中
    if ([_slnCaptureSession canAddOutput:_slnCaptureStillImageOutput]) {
        [_slnCaptureSession addOutput:_slnCaptureStillImageOutput];
    }
}
#pragma mark -- 录音机对象
-(void)setslnAudioRecorderMode:( SLNCameraMode) slnCameraMode{
        self.slnTimeRecordLabel.hidden = NO;
    //创建录音文件保存路径
    NSURL *url=[self getSavePath];
    //创建录音格式设置
    NSDictionary *setting=[self getAudioSetting];
    //创建录音机
    NSError *error=nil;
    _audioRecorder=[[AVAudioRecorder alloc]initWithURL:url settings:setting error:&error];
    _audioRecorder.delegate=self;
    _audioRecorder.meteringEnabled=YES;//如果要监控声波则必须设置为YES
    if (error) {
        NSLog(@"创建录音机对象时发生错误，错误信息：%@",error.localizedDescription);
    }
}
/**
 *  取得录音文件设置
 *
 *  @return 录音设置
 */
-(NSDictionary *)getAudioSetting{
    NSMutableDictionary *dicM=[NSMutableDictionary dictionary];
    //设置录音格式
    [dicM setObject:@(kAudioFormatLinearPCM) forKey:AVFormatIDKey];
    //设置录音采样率，8000是电话采样率，对于一般录音已经够了
    [dicM setObject:@(8000) forKey:AVSampleRateKey];
    //设置通道,这里采用单声道
    [dicM setObject:@(1) forKey:AVNumberOfChannelsKey];
    //每个采样点位数,分为8、16、24、32
    [dicM setObject:@(8) forKey:AVLinearPCMBitDepthKey];
    //是否使用浮点数采样
    [dicM setObject:@(YES) forKey:AVLinearPCMIsFloatKey];
    //....其他设置等
    return dicM;
}


/**
 *  取得指定位置的摄像头
 *
 *  @param position 摄像头位置
 *
 *  @return 摄像头设备
 */
-(AVCaptureDevice *)slnAssignCameraDeviceWithPosition:(AVCaptureDevicePosition )position{
    
    NSArray *cameras= [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *camera in cameras) {
        if ([camera position]==position) {
            return camera;
        }
    }
    return nil;
}

/**
 *  改变设备属性的统一操作方法
 *
 *  @param propertyChange 属性改变操作
 */
-(void)changeDeviceProperty:(PropertyChangeBlock)propertyChange{
    AVCaptureDevice *captureDevice= [self.slnCaptureDeviceInput device];
    NSError *error;
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }else{
        NSLog(@"设置设备属性过程发生错误，错误信息：%@",error.localizedDescription);
    }
}
/**
 *  设置闪光灯模式
 *
 *  @param flashMode 闪光灯模式
 */
-(void)setFlashMode:(AVCaptureFlashMode )flashMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFlashModeSupported:flashMode]) {
            [captureDevice setFlashMode:flashMode];
        }
    }];
}
/**
 *  设置手电筒模式
 *
 *  @param torchMode  手电筒模式
 */
-(void)setTorchMode:(AVCaptureTorchMode )torchMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isTorchModeSupported:torchMode]) {
            [captureDevice setTorchMode:torchMode];
        }
    }];
}
/**
 *  设置聚焦模式
 *
 *  @param focusMode 聚焦模式
 */
-(void)setFocusMode:(AVCaptureFocusMode )focusMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:focusMode];
        }
    }];
}
/**
 *  设置曝光模式
 *
 *  @param exposureMode 曝光模式
 */
-(void)setExposureMode:(AVCaptureExposureMode)exposureMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:exposureMode];
        }
    }];
}
/**
 *  设置聚焦点
 *
 *  @param point 聚焦点
 */
-(void)focusWithMode:(AVCaptureFocusMode)focusMode exposureMode:(AVCaptureExposureMode)exposureMode atPoint:(CGPoint)point{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        if ([captureDevice isFocusPointOfInterestSupported]) {
            [captureDevice setFocusPointOfInterest:point];
        }
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
        }
        if ([captureDevice isExposurePointOfInterestSupported]) {
            [captureDevice setExposurePointOfInterest:point];
        }
    }];
}
#pragma mark -- 添加手势
#pragma mark -- 添加点按手势--点按时聚焦
-(void)addGenstureRecognizer{
    UITapGestureRecognizer *tapGesture=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapScreen:)];
    [self.slnContainerView addGestureRecognizer:tapGesture];
}
#pragma mark -- 添加长按手势
-(void)addLongPressGenstureRecognizer{
    _slnPressRecognizer = [[UILongPressGestureRecognizer  alloc]initWithTarget:self action:@selector(slnLongPressGestureRecognizer:)];
    [_slnTakeButton addGestureRecognizer:_slnPressRecognizer];
}
-(void)removeLongPressGenstureRecognizer{
    if (_slnPressRecognizer) {
        
        [_slnTakeButton removeGestureRecognizer:_slnPressRecognizer];
    }
}
-(void)tapScreen:(UITapGestureRecognizer *)tapGesture{
    CGPoint point = [tapGesture locationInView:self.slnContainerView];
    //将UI坐标转化为摄像头坐标
    CGPoint cameraPoint = [self.slnCaptureVideoPreviewLayer captureDevicePointOfInterestForPoint:point];
    [self setFocusCursorWithPoint:point];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposureMode:AVCaptureExposureModeAutoExpose atPoint:cameraPoint];
}

/**
 *  设置聚焦光标位置
 *
 *  @param point 光标位置
 */
-(void)setFocusCursorWithPoint:(CGPoint)point{
    self.slnFocusCursorView.center = point;
    self.slnFocusCursorView.transform = CGAffineTransformMakeScale(1.5, 1.5);
    self.slnFocusCursorView.alpha = 1.0;
    [UIView animateWithDuration:1.0 animations:^{
        self.slnFocusCursorView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.slnFocusCursorView.alpha=0;
        
    }];
}
//关闭定时器
-(void)slnCannelRecordTimer{
    [_slnRecordTimer setFireDate:[NSDate distantFuture]];
}
//开启定时器
-(void)slnbeginRecordTimer{
   [_slnRecordTimer setFireDate:[NSDate distantPast]];
}



/**
 *  返回显示一个记录录制的时间字符串
 *
 *  @param  startTime 开始时间
 *  @param endTime 结束时间
 *  return  string
 */
- (NSString *)dateTimeDifferenceWithStartTime:(NSDate *)startTime endTime:(NSDate *)endTime{
    
    NSTimeInterval start = [startTime timeIntervalSince1970]*1;
    NSTimeInterval end = [endTime timeIntervalSince1970]*1;
    NSTimeInterval value = end - start;
    int second = (int)value %60;  //s
    int minute = (int)value /60%60;
    int hour = (int)value /3600;
    
    NSString *str;
    //    int hourDigit =  (int)[self slnNSIntegerLength:hour];
    //    int minuteDigit =  (int)[self slnNSIntegerLength:minute];
    //    int secondDigit =  (int)[self slnNSIntegerLength:second];
    //    if (hourDigit <2) {
    //        if (minuteDigit < 2) {
    //            if (secondDigit < 2) {
    //
    //                str = [NSString stringWithFormat:@"0%d:0%d:0%d",hour,minute,second];
    //                return str;
    //            }
    //            str = [NSString stringWithFormat:@"0%d:0%d:%d",hour,minute,second];
    //            return str;
    //        }else if (minuteDigit >= 2){
    //            if (secondDigit < 2) {
    //
    //                str = [NSString stringWithFormat:@"0%d:%d:0%d",hour,minute,second];
    //                return str;
    //            }
    //            str = [NSString stringWithFormat:@"0%d:%d:%d",hour,minute,second];
    //            return str;
    //        }
    //    }
    //
    //    if (minuteDigit < 2) {
    //        if (secondDigit < 2) {
    //
    //            str = [NSString stringWithFormat:@"%d:0%d:0%d",hour,minute,second];
    //            return str;
    //        }
    //        str = [NSString stringWithFormat:@"%d:0%d:%d",hour,minute,second];
    //        return str;
    //    }else if (minuteDigit >= 2){
    //        if (secondDigit < 2) {
    //
    //            str = [NSString stringWithFormat:@"%d:%d:0%d",hour,minute,second];
    //            return str;
    //        }
    //        str = [NSString stringWithFormat:@"%d:%d:%d",hour,minute,second];
    //        return str;
    //    }
    //    NSLog(@"小时位数：%d---分钟位数：%d---秒位数%d",hourDigit,minuteDigit,secondDigit);
    
    
    if (hour < 10){
        if (minute < 10) {
            if (second < 10) {
                
                str = [NSString stringWithFormat:@"0%d:0%d:0%d",hour,minute,second];
                return str;
            }
            str = [NSString stringWithFormat:@"0%d:0%d:%d",hour,minute,second];
            return str;
        }else if (minute >= 10){
            if (second < 10) {
                
                str = [NSString stringWithFormat:@"0%d:%d:0%d",hour,minute,second];
                return str;
            }
            str = [NSString stringWithFormat:@"0%d:%d:%d",hour,minute,second];
            return str;
        }
        return str;
    }
    
    if (minute < 10) {
        if (second < 10) {
            
            str = [NSString stringWithFormat:@"%d:0%d:0%d",hour,minute,second];
            return str;
        }
        str = [NSString stringWithFormat:@"%d:0%d:%d",hour,minute,second];
        return str;
    }else if (minute >= 10){
        if (second < 10) {
            
            str = [NSString stringWithFormat:@"%d:%d:0%d",hour,minute,second];
            return str;
        }
        str = [NSString stringWithFormat:@"%d:%d:%d",hour,minute,second];
        return str;
    }
    return str;
}
#pragma mark -- 整型的个数
- (NSInteger)slnNSIntegerLength:(NSInteger)x {
    NSInteger sum = 0 , j=1;
    if (x == 0) {
        return 1;
    }
    while( x >= 1 ) {
        //        NSLog(@"%zd位数是 : %zd\n",j,x%10);
        x = x/10;
        sum++;
        j = j*10;
    }
    
    //    NSLog(@"你输入的是一个%zd位数\n",sum);
    return sum;
}

#pragma mark -- 保存照片
//把图片保存到系统相册
-(void)slnSavePicture{
    //1.根据设备输出对象获得连接
//    AVCaptureConnection *captureConnection = [self.slnCaptureStillImageOutput connectionWithMediaType:AVMediaTypeVideo];
    //2.根据连接取得设备输出的数据
    [self.slnCaptureStillImageOutput captureStillImageAsynchronouslyFromConnection:[self.slnCaptureStillImageOutput connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        if (imageDataSampleBuffer) {
            
            NSData *imageData=[AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
            UIImage *image=[UIImage imageWithData:imageData];
            _slnSavePic = image;
            [self saveImageIntoAlbum];
            //1.简单地把图片保存的系统相册
//            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
            //2.AssetsLibrary框架 保存图片
            //            ALAssetsLibrary *assetsLibrary=[[ALAssetsLibrary alloc]init];
            //            [assetsLibrary writeImageToSavedPhotosAlbum:[image CGImage] orientation:(ALAssetOrientation)[image imageOrientation] completionBlock:nil];
        }
        
    }];

}
//回调判断保存是否成功
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (error) {
        //保存失败
    }else{
        //保存成功
    }
}

#pragma mark --  添加自定义相册

// 获得刚才添加到【相机胶卷】中的图片
-(PHFetchResult<PHAsset *> *)createdAssets
{
    __block NSString *createdAssetId = nil;
    // 添加图片到【相机胶卷】
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        createdAssetId = [PHAssetChangeRequest creationRequestForAssetFromImage:_slnSavePic].placeholderForCreatedAsset.localIdentifier;
    } error:nil];
    if (createdAssetId == nil) return nil;
    // 在保存完毕后取出图片
    return [PHAsset fetchAssetsWithLocalIdentifiers:@[createdAssetId] options:nil];
}
//获得自定义相册
-(PHAssetCollection *)createdCollection
{
    // app的名字可以作为相册的名字，否则自己设定需要的相册名字
    NSString *title = [NSBundle mainBundle].infoDictionary[(NSString *)kCFBundleNameKey];
    // 获得所有的自定义相册
    /*
        PHAssetCollectionTypeSmartAlbum   PHAssetCollectionSubtypeAlbumRegular  获取系统的相册
        PHAssetCollectionTypeAlbum   获得所有的自定义相册
        PHAssetCollectionTypeMoment   可以获取地址等
     
     */
    PHFetchResult<PHAssetCollection *> *collections = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    for (PHAssetCollection *collection in collections) {
        if ([collection.localizedTitle isEqualToString:title]) {
            return collection;
        }
    }
    // 代码执行到这里，说明还没有自定义相册
    __block NSString *createdCollectionId = nil;
    // 创建一个新的相册
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        createdCollectionId = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:title].placeholderForCreatedAssetCollection.localIdentifier;
    } error:nil];
    if (createdCollectionId == nil) return nil;
    // 创建完毕后再取出相册
    return [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[createdCollectionId] options:nil].firstObject;
}
//保存图片到相册
-(void)saveImageIntoAlbum
{
    // 获得相片
    PHFetchResult<PHAsset *> *createdAssets = self.createdAssets;
    // 获得相册
    PHAssetCollection *createdCollection = self.createdCollection;
    if (createdAssets == nil || createdCollection == nil) {
        NSLog(@"保存失败");
        return;
    }
    // 将相片添加到相册
    NSError *error = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetCollectionChangeRequest *request = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:createdCollection];
        [request insertAssets:createdAssets atIndexes:[NSIndexSet indexSetWithIndex:0]];
    } error:&error];
    // 保存结果
    if (error) {
        NSLog(@"保存失败");
    } else {
        NSLog(@"保存成功");
    }
}
/**
 *  取得录音文件保存路径
 *
 *  @return 录音文件路径
 */
-(NSURL *)getSavePath{
    NSString *urlStr=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    urlStr = [urlStr stringByAppendingPathComponent:kRecordAudioFile];
    NSLog(@"file path:%@",urlStr);
    NSURL *url = [NSURL fileURLWithPath:urlStr];
    return url;
}

//将创建日期作为文件名
+(NSString*)getFormatedDateStringOfDate:(NSDate*)date{
    
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setTimeZone:[NSTimeZone localTimeZone]];
    //注意时间的格式：MM表示月份，mm表示分钟，HH用24小时制，小hh是12小时制。
    [dateFormatter setDateFormat:@"yyyyMMddHHmmss"];
    NSString* dateString = [dateFormatter stringFromDate:date];
    return dateString;
}

@end
