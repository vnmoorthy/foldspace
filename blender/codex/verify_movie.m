// Native Apple decoder verification: software FFmpeg only reports the HEVC base layer.
// clang -fobjc-arc -framework Foundation -framework AVFoundation -framework CoreMedia \
//   -framework CoreVideo blender/codex/verify_movie.m -o blender/codex/out/verify_movie
// blender/codex/out/verify_movie assets/video/blackhole-loop.mov
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <math.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc != 2) { fprintf(stderr,"usage: verify_movie path.mov\n"); return 2; }
        NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        dispatch_semaphore_t ready=dispatch_semaphore_create(0);
        __block AVAssetTrack *track=nil;
        __block NSError *loadError=nil;
        [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *err) {
            track=tracks.firstObject; loadError=err; dispatch_semaphore_signal(ready);
        }];
        dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC));
        if (!track) { fprintf(stderr,"No video track: %s\n",loadError.description.UTF8String); return 1; }
        BOOL alphaCharacteristic = [track hasMediaCharacteristic:AVMediaCharacteristicContainsAlphaChannel];
        NSError *error = nil;
        AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
        NSDictionary *settings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
        output.alwaysCopiesSampleData = NO;
        [reader addOutput:output];
        if (![reader startReading]) { fprintf(stderr,"%s\n",reader.error.description.UTF8String); return 1; }
        NSUInteger count=0, width=0, height=0, clear=0, opaque=0, partial=0;
        int amin=255,amax=0;
        NSMutableData *first=nil, *last=nil, *previous=nil;
        double adjacentTotal=0, maxAdjacent=0;
        while (reader.status == AVAssetReaderStatusReading) {
            @autoreleasepool {
                CMSampleBufferRef sample = [output copyNextSampleBuffer];
                if (!sample) break;
                CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(sample);
                CVPixelBufferLockBaseAddress(pixels,kCVPixelBufferLock_ReadOnly);
                width=CVPixelBufferGetWidth(pixels); height=CVPixelBufferGetHeight(pixels);
                size_t stride = CVPixelBufferGetBytesPerRow(pixels);
                unsigned char *base=CVPixelBufferGetBaseAddress(pixels);
                NSMutableData *compact=[NSMutableData dataWithLength:width*height*4];
                unsigned char *bytes=compact.mutableBytes;
                for (NSUInteger y=0;y<height;y++) {
                    memcpy(bytes+y*width*4,base+y*stride,width*4);
                    if (count==0) for (NSUInteger x=0;x<width;x++) {
                        int a=base[y*stride+x*4+3];
                        amin=MIN(amin,a); amax=MAX(amax,a);
                        if (a==0) clear++; else if(a==255) opaque++; else partial++;
                    }
                }
                CVPixelBufferUnlockBaseAddress(pixels,kCVPixelBufferLock_ReadOnly);
                if (!first) first=compact;
                if (previous) {
                    const unsigned char *p=previous.bytes;
                    double d=0;
                    for(NSUInteger j=0;j<compact.length;j++) d+=abs((int)bytes[j]-p[j]);
                    d/=compact.length;
                    adjacentTotal+=d; maxAdjacent=MAX(maxAdjacent,d);
                }
                previous=compact; last=compact;
                count++;
                CFRelease(sample);
            }
        }
        if (reader.status == AVAssetReaderStatusFailed || !count) {
            fprintf(stderr,"Decode failed: %s\n",reader.error.description.UTF8String); return 1;
        }
        const unsigned char *f=first.bytes, *l=last.bytes;
        double seam=0;
        for(NSUInteger j=0;j<first.length;j++) seam+=abs((int)f[j]-l[j]);
        seam/=first.length;
        NSDictionary *report=@{@"codec":@"HEVC", @"contains_alpha_characteristic":@(alphaCharacteristic),
            @"decoded_frames":@(count), @"width":@(width), @"height":@(height),
            @"duration_seconds":@(CMTimeGetSeconds(asset.duration)), @"fps":@(track.nominalFrameRate),
            @"alpha_min":@(amin), @"alpha_max":@(amax), @"transparent_pixels_first_frame":@(clear),
            @"opaque_pixels_first_frame":@(opaque), @"partial_alpha_pixels_first_frame":@(partial),
            @"mean_adjacent_frame_byte_delta":@(adjacentTotal/MAX((double)count-1,1)),
            @"max_adjacent_frame_byte_delta":@(maxAdjacent), @"last_to_first_byte_delta":@(seam)};
        NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return (alphaCharacteristic && amin==0 && amax==255) ? 0 : 1;
    }
}
