
//  encoder.c
//  artFileTool
//
//  Created by Alex Zielenski on 6/10/11.
//  Copyright 2011 Alex Zielenski. All rights reserved.
//

#include "Defines.h"
#include "encoder.h"

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Accelerate/Accelerate.h>

static int globalCounter;
unsigned char* dataFromRep(NSBitmapImageRep *bitmapImageRep, BOOL unpremultiply, BOOL abgr);

static unsigned char* bytesFromCGImage(CGImageRef image, uint16_t *w, uint16_t *h) {
	if (!image)
		return NULL;
	
	CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(image);
		
	NSInteger width = CGImageGetWidth(image);
    NSInteger height = CGImageGetHeight(image);
	
    if (w != NULL) { *w = (uint16_t)width; }
    if (h != NULL) { *h = (uint16_t)height; }
	
    
	CGDataProviderRef provider = CGImageGetDataProvider(image);
	CFDataRef data = CGDataProviderCopyData(provider);
	
	UInt8* bytes = malloc(width * height * 4);
	CFDataGetBytes(data, CFRangeMake(0, CFDataGetLength(data)), bytes);
	CFRelease(data);
	
	vImage_Buffer src;
	src.data = (void*)bytes;
	src.rowBytes = 4 * width;
	src.width = width;
	src.height = height;
	
	BOOL alphaFirst    = (alphaInfo == kCGImageAlphaFirst || alphaInfo == kCGImageAlphaPremultipliedFirst);
	BOOL premultiplied = (alphaInfo == kCGImageAlphaPremultipliedFirst || alphaInfo == kCGImageAlphaPremultipliedLast);
	BOOL little        = (CGImageGetBitmapInfo(image) == kCGBitmapByteOrder32Little);
	
	uint8_t permuteMap[4];
	if (alphaFirst) {
		if (little) {
			// BGRA to BGRA
			permuteMap[0] = 0;
			permuteMap[1] = 1;
			permuteMap[2] = 2;
			permuteMap[3] = 3;
		} else {
			// ARGB to BGRA
			permuteMap[0] = 3;
			permuteMap[1] = 2;
			permuteMap[2] = 1;
			permuteMap[3] = 0;
		}
	} else {
		if (little) {
			// ABGR to BGRA
			permuteMap[0] = 1;
			permuteMap[1] = 2;
			permuteMap[2] = 3;
			permuteMap[3] = 0;
		} else {
			// RGBA to BGRA
			permuteMap[0] = 2;
			permuteMap[1] = 1;
			permuteMap[2] = 0;
			permuteMap[3] = 3;
		}
	}
	
	vImagePermuteChannels_ARGB8888(&src, &src, permuteMap, 0);
	
	if (premultiplied) {
		vImageUnpremultiplyData_BGRA8888(&src, &src, 0);
	}
	
	return src.data;
}

static BOOL encodeImages(NSString *folderPath, NSString *destinationPath) {
	NSMutableData *fileData = [[NSMutableData alloc] initWithCapacity:0];
	NSMutableData *headerData;
	
	headerData = [[artFileData subdataWithRange:NSMakeRange(0, header.file_data_section_offset)] mutableCopy];
	// really nothing to do here except change some file offsets and sizes
	for (int idx = 0; idx < header.file_count; idx++) {
		NSMutableData *currentFileData = [[NSMutableData alloc] initWithCapacity:0];
		
		// we need to get the tags of the file to find the actual file location
		struct file_descriptor fd = descriptorForIndex(idx);		
		struct art_header ah = artHeaderFromDescriptor(fd);
		
		// edit the file descriptor
		fd.file_data_offset = (uint32_t)[fileData length];
		
		// write the file descriptor
		[headerData replaceBytesInRange:NSMakeRange(header.file_descriptors_offset + sizeof(struct file_descriptor)*idx, sizeof(struct file_descriptor))
							  withBytes:&fd];
		
		// find the path where out images are
		NSString *currentFolderPath = folderPath;
		for (int x = 0; x<sizeof(fd.tags); x++) {
			uint8_t y = fd.tags[x];
			if (y==0) {
				continue;
			}
			NSString *key = [[NSNumber numberWithInt:y] stringValue];
			if (!connect)
				currentFolderPath = [currentFolderPath stringByAppendingPathComponent:[tagNames objectForKey:key]];
			else
				currentFolderPath = [currentFolderPath stringByAppendingFormat:@"%@%@", (x==0) ? @"/" : @".", [tagNames objectForKey:key]];
		}
		
		int subImageCount = ah.art_rows*ah.art_columns;
		if (!connect) {
			for (int x = 0; x < subImageCount; x++) {
				// write the details on
				NSString *filePath = [currentFolderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%i.png", globalCounter]];
				
				NSData *tempData = [NSData dataWithContentsOfFile:filePath];
				if (!tempData) {
					// apple sometimes says that there are images that don't exist
					continue;
				}
				
				uint16_t width;
				uint16_t height;
				
				CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)tempData);
				CGImageRef image = CGImageCreateWithPNGDataProvider(provider, NULL, false, kCGRenderingIntentDefault);
				unsigned char *bytes = bytesFromCGImage(image, &width, &height);
				
				// set the goods
				ah.subimage_heights[x] = height;
				ah.subimage_widths[x] = width;
				ah.subimage_offsets[x] = (uint32_t)((int)[currentFileData length] + (int)sizeof(struct art_header));
				
				// append the data bytes
				[currentFileData appendBytes:bytes length:width*height*4];
				
				globalCounter++;
				
			}
		} else {
			NSString *filePath = [currentFolderPath stringByAppendingPathExtension:@"png"];
			NSData *tempData = [NSData dataWithContentsOfFile:filePath];
			if (!tempData)
				continue;
			
			// split into pieces
			int currentX;
			int currentY = 0;

			CGDataProviderRef prov = CGDataProviderCreateWithCFData((CFDataRef)tempData);
			CGImageRef totalImage = CGImageCreateWithPNGDataProvider(prov, NULL, false, kCGRenderingIntentDefault);
			CGDataProviderRelease(prov);
			
			for (int x = 0; x<ah.art_rows; x++) {
				uint32_t offset = ((int)[currentFileData length] + (int)sizeof(struct art_header));
				currentX=0;
				
				for (int y = 0; y<ah.art_columns; y++) {
					uint32_t ci = x*ah.art_columns + y;
					uint16_t width = ah.subimage_widths[ci];
					uint16_t height = ah.subimage_heights[ci];
					
					if (width<=0||height<=0) {
						ah.subimage_heights[ci] = (uint16_t)height;
						ah.subimage_widths[ci] = (uint16_t)width;
						ah.subimage_offsets[ci] = (uint32_t)offset;
						continue;
					}
					
					CGRect r = CGRectMake(currentX, currentY, width, height);
					CGImageRef newRef = CGImageCreateWithImageInRect(totalImage, r);
					
					unsigned char * bytes = bytesFromCGImage(newRef,
															 NULL, NULL);
					
					
					
					
					currentX+=width;
					
					// set the goods
					ah.subimage_heights[ci] = height;
					ah.subimage_widths[ci] = width;
					ah.subimage_offsets[ci] = offset;
					
					offset+=4*width*height;
					
					[currentFileData appendBytes:bytes length:4*width*height];
					
					if (y==ah.art_columns-1)
						currentY+=height;
					
				}

			}
			CGImageRelease(totalImage);
		}
		
		printf("Encoded File Index : %i\n", idx);
		
		[fileData appendBytes:&ah length:(int)sizeof(struct art_header)];
		[fileData appendData:currentFileData];
		[currentFileData release];
	}
	[headerData appendData:fileData];
	[headerData writeToFile:destinationPath atomically:NO];
	
	[fileData release];
	[headerData release];
	
	return YES;
}

BOOL artfile_encode(NSString *folderPath, NSString *originalPath, NSString *destinationPath) {
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir;
	BOOL exists = [fm fileExistsAtPath:folderPath isDirectory:&isDir];
	if (!exists) {
		NSError *err = nil;
		[fm createDirectoryAtPath:folderPath 
	  withIntermediateDirectories:YES 
					   attributes:nil 
							error:&err];
		if (err!=nil) {
			printf("Error creating directory %s. May be a permissions issue\n", [folderPath UTF8String]);
		}
	} else if (exists&&!isDir) {
		printf("%s is not a directory.\n", [folderPath UTF8String]);
		return NO;
	}
	exists = [fm fileExistsAtPath:originalPath isDirectory:&isDir];
	if (exists&&isDir) {
		printf("%s is a directory.\n", [originalPath UTF8String]);
		return NO;
	} else if (!exists) {
		printf("%s doesn't exist.\n", [originalPath UTF8String]);
		return NO;
	}
	
	exists = [fm fileExistsAtPath:destinationPath isDirectory:&isDir];
	if (exists&&isDir) {
		printf("%s is a directory.\n", [destinationPath UTF8String]);
		return NO;
	}
	
	artFileData = [[NSData alloc] initWithContentsOfFile:originalPath];
	[artFileData getBytes:&header length:(int)sizeof(struct file_header)];
	
	tagNames = [[NSMutableDictionary dictionaryWithCapacity:(int)header.tag_count] retain];
	readTagDescriptors();
	
	encodeImages(folderPath, destinationPath);
	[artFileData release];
	artFileData = nil;
	[tagNames release];
	tagNames = nil;
	
	return YES;
}