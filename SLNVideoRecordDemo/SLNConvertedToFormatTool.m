//
//  slConvertedToFormatTool.m
//  SLNVideoRecordDemo
//
//  Created by 乔冬 on 17/4/13.
//  Copyright © 2017年 XinHuaTV. All rights reserved.
//

#import "SLNConvertedToFormatTool.h"
#import <AVFoundation/AVFoundation.h>
@implementation SLNConvertedToFormatTool
+(void)slConvertedIntoMP4WithFileUrl:(NSURL *)fileUrl
                             success:(void(^)(id response ))success
                             failure:(void(^)(id error))failure
{
    NSURL *filePathURL = fileUrl;
    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:filePathURL  options:nil];
    
    NSDateFormatter* formater = [[NSDateFormatter alloc] init];
    [formater setDateFormat:@"yyyyMMddHHmmssSSS"];
    
    NSString *fileName = [NSString stringWithFormat:@"output_%@.mp4",[formater stringFromDate:[NSDate date]]];
    NSString *outFilePath = [NSHomeDirectory() stringByAppendingFormat:@"/Documents/%@", fileName];
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:avAsset];
    if ([compatiblePresets containsObject:AVAssetExportPresetMediumQuality]) {
        
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset presetName:AVAssetExportPresetMediumQuality];
        
        exportSession.outputURL = [NSURL fileURLWithPath:outFilePath];
        exportSession.outputFileType = AVFileTypeMPEG4;
        
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            if ([exportSession status] == AVAssetExportSessionStatusCompleted) {
                NSLog(@"AVAssetExportSessionStatusCompleted---转换成功");
                NSString *filePath = outFilePath;
                NSURL *filePathURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@",outFilePath]];
                NSLog(@"转换完成_filePath = %@\\n_filePathURL = %@",filePath,filePathURL);
                success (filePathURL);
                
            }else{
                NSLog(@"转换失败,状态为:%li,可能的原因:%@",(long)[exportSession status],[[exportSession error] localizedDescription]);
                NSString *error = [[exportSession error] localizedDescription];
                
                failure(error);
            }
        }];
    }
}
@end
