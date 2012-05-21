//
//  main.m
//  artFileTool
//
//  Copyright (c) 2011-2012, Alex Zielenski
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification, are permitted provided 
//  that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice, this list of conditions and the 
//    following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the 
//    following disclaimer in the documentation and/or other materials provided with the distribution.
//  * Any redistribution, use, or modification is done solely for personal benefit and not for any commercial 
//    purpose or for monetary gain

//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS 
//  OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY 
//  AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS 
//  BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
//  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY 
//  OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import <Foundation/Foundation.h>
#import "ArtFile.h"
#include <mach/mach_time.h>

static const char *help = "Usage:\n\tDecode: [-os 10.8|10.8.2|etc] -d filePath exportDirectory\n\tEncode: -e imageDirectory newFilePath\n";
int main (int argc, const char * argv[])
{

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    if (argc <= 2) {
        printf(help, NULL);
        return 1;
    }
    
    BOOL encode;
    BOOL pdf;
    
    int majorOS  = -1;
    int minorOS  = 0;
    int bugFixOS = 0;
    
	int startIdx = 0;
    
	for (int x = 1; x < argc; x++) {
		if ((!strcmp(argv[x], "-os"))) {
            NSString *os = [NSString stringWithUTF8String:argv[x + 1]];
            NSArray *delimited = [os componentsSeparatedByString:@"."];
            
            for (int idx = 0; idx < delimited.count; idx++) {
                NSNumber *num = [delimited objectAtIndex:idx];
                int vers = num.intValue;
                
                if (idx == 0)
                    majorOS = vers;
                else if (idx == 1)
                    minorOS = vers;
                else if (idx == 2)
                    bugFixOS = vers;
                
            }
            
			continue;
		} else if  ((!strcmp(argv[x], "-d"))) {
			encode = NO;
			continue;
		} else if  ((!strcmp(argv[x], "-e"))) {
			encode = YES;
			continue;
        } else if ((!strcmp(argv[x], "-h")) || (!strcmp(argv[x], "-help")) || (!strcmp(argv[x], "?"))) {
            printf(help, NULL);
            return 1;
            break;
        } else if ((!strcmp(argv[x], "-pdf"))) { // hidden option
            pdf = YES;   
            continue;
		} else {
			startIdx = x - 1;
			continue;
		}
	}
    
    NSString *path1 = nil, *path2 = nil;
    
    if (argc -1 <= startIdx) {
        
        if (!encode) {
            path1 = [[ArtFile artFileURL] path];
            startIdx--;
            
        } else {
            NSLog(@"Missing arguments");
            printf(help, NULL);
            return 1;
        }
    }
    
    if (!path1)
        path1 = [NSString stringWithUTF8String:argv[startIdx]];
    
    path2 = [NSString stringWithUTF8String:argv[startIdx + 1]];
    
    path1 = [path1 stringByExpandingTildeInPath];
    path2 = [path2 stringByExpandingTildeInPath];
    
    uint64_t start = mach_absolute_time();

    if (encode) {
        ArtFile *file = [ArtFile artFileWithFolderAtURL:[NSURL fileURLWithPath:path1]];
        [file.data writeToFile:path2 atomically:NO];
    } else {
        ArtFile *file = [ArtFile artFileWithFileAtURL:[NSURL fileURLWithPath:path1] 
                                              majorOS:majorOS 
                                              minorOS:minorOS 
                                             bugFixOS:bugFixOS];
        
        NSError *err = nil;
        [file decodeToFolder:[NSURL fileURLWithPath:path2] error:&err];
        
        if (err)
            NSLog(@"%@", err.localizedFailureReason);
        
    }
	
#ifdef DEBUG
    uint64_t end = mach_absolute_time();
    uint64_t elapsed = end - start;
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    uint64_t nanoSeconds = elapsed * info.numer / info.denom;

    printf ("elapsed time was %lld nanoseconds\n", nanoSeconds);
#endif
    
    [pool drain];
    return 0;
}

