//
//  slConvertedToFormatTool.h
//  SLNVideoRecordDemo
//
//  Created by 乔冬 on 17/4/13.
//  Copyright © 2017年 XinHuaTV. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SLNConvertedToFormatTool : NSObject
+(void)slConvertedIntoMP4WithFileUrl:(NSURL *)fileUrl
                             success:(void(^)(id response ))success
                             failure:(void(^)(id error))failure;
@end
