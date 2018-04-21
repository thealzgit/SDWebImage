/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageLoader.h"
#import "SDWebImageCacheKeyFilter.h"
#import "SDWebImageCodersManager.h"
#import "SDWebImageCoderHelper.h"
#import "SDAnimatedImage.h"
#import "UIImage+WebCache.h"
#import "objc/runtime.h"

static void * SDWebImageLoaderProgressiveCoderKey = &SDWebImageLoaderProgressiveCoderKey;

UIImage * _Nullable SDWebImageLoaderDecodeImageData(NSData * _Nonnull imageData, NSURL * _Nonnull imageURL, SDWebImageOptions options, SDWebImageContext * _Nullable context) {
    NSCParameterAssert(imageData);
    NSCParameterAssert(imageURL);
    
    UIImage *image;
    id<SDWebImageCacheKeyFilter> cacheKeyFilter = [context valueForKey:SDWebImageContextCacheKeyFilter];
    NSString *cacheKey;
    if (cacheKeyFilter) {
        cacheKey = [cacheKeyFilter cacheKeyForURL:imageURL];
    } else {
        cacheKey = imageURL.absoluteString;
    }
    BOOL decodeFirstFrame = options & SDWebImageDecodeFirstFrameOnly;
    NSNumber *scaleValue = [context valueForKey:SDWebImageContextImageScaleFactor];
    CGFloat scale = scaleValue.doubleValue >= 1 ? scaleValue.doubleValue : SDImageScaleFactorForKey(cacheKey);
    if (scale < 1) {
        scale = 1;
    }
    if (!decodeFirstFrame) {
        // check whether we should use `SDAnimatedImage`
        if ([context valueForKey:SDWebImageContextAnimatedImageClass]) {
            Class animatedImageClass = [context valueForKey:SDWebImageContextAnimatedImageClass];
            if ([animatedImageClass isSubclassOfClass:[UIImage class]] && [animatedImageClass conformsToProtocol:@protocol(SDAnimatedImage)]) {
                image = [[animatedImageClass alloc] initWithData:imageData scale:scale];
                if (options & SDWebImagePreloadAllFrames && [image respondsToSelector:@selector(preloadAllFrames)]) {
                    [((id<SDAnimatedImage>)image) preloadAllFrames];
                }
            }
        }
    }
    if (!image) {
        image = [[SDWebImageCodersManager sharedManager] decodedImageWithData:imageData options:@{SDWebImageCoderDecodeFirstFrameOnly : @(decodeFirstFrame), SDWebImageCoderDecodeScaleFactor : @(scale)}];
    }
    if (image) {
        BOOL shouldDecode = (options & SDWebImageAvoidDecodeImage) == 0;
        if ([image conformsToProtocol:@protocol(SDAnimatedImage)]) {
            // `SDAnimatedImage` do not decode
            shouldDecode = NO;
        } else if (image.sd_isAnimated) {
            // animated image do not decode
            shouldDecode = NO;
        }
        
        if (shouldDecode) {
            BOOL shouldScaleDown = options & SDWebImageScaleDownLargeImages;
            if (shouldScaleDown) {
                image = [SDWebImageCoderHelper decodedAndScaledDownImageWithImage:image limitBytes:0];
            } else {
                image = [SDWebImageCoderHelper decodedImageWithImage:image];
            }
        }
    }
    
    return image;
}

UIImage * _Nullable SDWebImageLoaderDecodeProgressiveImageData(NSData * _Nonnull imageData, NSURL * _Nonnull imageURL, BOOL finished,  id<SDWebImageOperation> _Nonnull operation, SDWebImageOptions options, SDWebImageContext * _Nullable context) {
    NSCParameterAssert(imageData);
    NSCParameterAssert(imageURL);
    NSCParameterAssert(operation);
    
    id<SDWebImageProgressiveCoder> progressiveCoder = objc_getAssociatedObject(operation, SDWebImageLoaderProgressiveCoderKey);
    if (!progressiveCoder) {
        // We need to create a new instance for progressive decoding to avoid conflicts
        for (id<SDWebImageCoder>coder in [SDWebImageCodersManager sharedManager].coders) {
            if ([coder conformsToProtocol:@protocol(SDWebImageProgressiveCoder)] &&
                [((id<SDWebImageProgressiveCoder>)coder) canIncrementalDecodeFromData:imageData]) {
                progressiveCoder = [[[coder class] alloc] initIncrementalWithOptions:nil];
                break;
            }
        }
        objc_setAssociatedObject(operation, SDWebImageLoaderProgressiveCoderKey, progressiveCoder, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // If we can't find any progressive coder, disable progressive download
    if (!progressiveCoder) {
        return nil;
    }
    
    UIImage *image;
    id<SDWebImageCacheKeyFilter> cacheKeyFilter = [context valueForKey:SDWebImageContextCacheKeyFilter];
    NSString *cacheKey;
    if (cacheKeyFilter) {
        cacheKey = [cacheKeyFilter cacheKeyForURL:imageURL];
    } else {
        cacheKey = imageURL.absoluteString;
    }
    BOOL decodeFirstFrame = options & SDWebImageDecodeFirstFrameOnly;
    NSNumber *scaleValue = [context valueForKey:SDWebImageContextImageScaleFactor];
    CGFloat scale = scaleValue.doubleValue >= 1 ? scaleValue.doubleValue : SDImageScaleFactorForKey(cacheKey);
    if (scale < 1) {
        scale = 1;
    }
    
    [progressiveCoder updateIncrementalData:imageData finished:finished];
    if (!decodeFirstFrame) {
        // check whether we should use `SDAnimatedImage`
        if ([context valueForKey:SDWebImageContextAnimatedImageClass]) {
            Class animatedImageClass = [context valueForKey:SDWebImageContextAnimatedImageClass];
            if ([animatedImageClass isSubclassOfClass:[UIImage class]] && [animatedImageClass conformsToProtocol:@protocol(SDAnimatedImage)] && [progressiveCoder conformsToProtocol:@protocol(SDWebImageAnimatedCoder)]) {
                image = [[animatedImageClass alloc] initWithAnimatedCoder:(id<SDWebImageAnimatedCoder>)progressiveCoder scale:scale];
            }
        }
    }
    if (!image) {
        image = [progressiveCoder incrementalDecodedImageWithOptions:@{SDWebImageCoderDecodeFirstFrameOnly : @(decodeFirstFrame), SDWebImageCoderDecodeScaleFactor : @(scale)}];
    }
    if (image) {
        BOOL shouldDecode = (options & SDWebImageAvoidDecodeImage) == 0;
        if ([image conformsToProtocol:@protocol(SDAnimatedImage)]) {
            // `SDAnimatedImage` do not decode
            shouldDecode = NO;
        } else if (image.sd_isAnimated) {
            // animated image do not decode
            shouldDecode = NO;
        }
        if (shouldDecode) {
            image = [SDWebImageCoderHelper decodedImageWithImage:image];
        }
        // mark the image as progressive (completionBlock one are not mark as progressive)
        image.sd_isIncremental = YES;
    }
    
    return image;
}

SDWebImageContextOption const SDWebImageContextLoaderCachedImage = @"loaderCachedImage";
