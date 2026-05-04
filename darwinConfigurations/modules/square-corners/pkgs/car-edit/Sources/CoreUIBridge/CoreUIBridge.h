// Bridging declarations for Apple's private CoreUI.framework.
// Written from scratch based on the symbols Samra (MIT) calls into; not
// vendored from any third party. We declare only what `car-edit` actually
// uses for read + replace + save of WindowShapeEdges renditions.

#ifndef CoreUIBridge_h
#define CoreUIBridge_h

@import Foundation;
@import CoreGraphics;

struct renditionkeytoken {
  unsigned short identifier;
  unsigned short value;
};

NS_ASSUME_NONNULL_BEGIN

@interface CUICommonAssetStorage : NSObject
- (nullable instancetype)initWithPath:(NSString *)path
                           forWriting:(BOOL)forWriting;
- (NSArray *)allRenditionNames;
- (nullable NSData *)assetForKey:(NSData *)key;
- (void)enumerateKeysAndObjectsUsingBlock:
    (void (^)(const struct renditionkeytoken *keyList, NSData *csiData))block;
- (long long)maximumRenditionKeyTokenCount;
@end

@interface CUIMutableCommonAssetStorage : CUICommonAssetStorage
- (BOOL)setAsset:(NSData *)data forKey:(NSData *)key;
- (BOOL)writeToDiskAndCompact:(BOOL)compact
    NS_SWIFT_NAME(writeToDisk(compact:));
@end

@interface CUIRenditionKey : NSObject
- (const struct renditionkeytoken *)keyList;
@end

@class CUIThemeRendition;

@interface CUIRenditionSliceInformation : NSObject
- (NSEdgeInsets)edgeInsets;
- (CGRect)destinationRect;
- (long long)renditionType;
- (CGSize)_topLeftCapSize;
- (CGSize)_bottomRightCapSize;
@end

@interface CUINamedLookup : NSObject
@property(copy, nonatomic) NSString *name;
@property(copy, nonatomic) CUIRenditionKey *key;
@property(readonly, nonatomic, getter=_rendition) CUIThemeRendition *rendition;
@end

@interface CUIStructuredThemeStore : NSObject
- (nullable NSData *)convertRenditionKeyToKeyData:
    (const struct renditionkeytoken *)keyList;
@end

@interface CUICatalog : NSObject
- (nullable instancetype)initWithURL:(NSURL *)url
                               error:(NSError *_Nullable *_Nullable)error;
- (void)enumerateNamedLookupsUsingBlock:
    (void (^)(CUINamedLookup *namedAsset))block;
- (CUIStructuredThemeStore *)_themeStore;
@end

@interface CUIThemeRendition : NSObject
// Newer macOS (>= Sequoia or so) added the 2-arg form; Tahoe runtime ships
// only the 3-arg form, so we declare the 3-arg version and always pass 0.
- (nullable instancetype)initWithCSIData:(NSData *)csiData
                                  forKey:
                                      (const struct renditionkeytoken *)keyList
                                 version:(unsigned int)version;
- (CGSize)unslicedSize;
- (CGRect)_destinationFrame;
- (long long)type;
- (unsigned int)subtype;
- (int)pixelFormat;
- (double)scale;
- (BOOL)isInternalLink;
- (NSString *)name;
- (nullable CUIRenditionKey *)linkingToRendition;
- (nullable CUIRenditionSliceInformation *)sliceInformation;
// Metadata copied into a CSIGenerator via prepareToEdit(for:).
@property(readonly, nonatomic) int blendMode;
@property(readonly, nonatomic) int exifOrientation;
@property(readonly, nonatomic) double opacity;
- (unsigned long long)colorSpaceID;
- (long long)templateRenderingMode;
- (nullable NSString *)utiType;
- (BOOL)isVectorBased;
@end

@interface CSIBitmapWrapper : NSObject
- (nullable instancetype)initWithPixelWidth:(unsigned int)width
                                pixelHeight:(unsigned int)height;
- (CGContextRef)bitmapContext;
@end

@interface CSIGenerator : NSObject
- (nullable instancetype)initWithCanvasSize:(CGSize)canvasSize
                                 sliceCount:(unsigned int)sliceCount
                                     layout:(short)layout;
- (void)addBitmap:(CSIBitmapWrapper *)bitmap;
- (void)addSliceRect:(CGRect)rect;
- (nullable NSData *)CSIRepresentationWithCompression:(BOOL)compression
    NS_SWIFT_NAME(csiRepresentation(withCompression:));
// Settable metadata — populated from the source rendition before encoding.
@property(copy, nonatomic) NSString *name;
@property(nonatomic) int blendMode;
@property(nonatomic) short colorSpaceID;
@property(nonatomic) int exifOrientation;
@property(nonatomic) double opacity;
@property(nonatomic) unsigned int scaleFactor;
@property(nonatomic) long long templateRenderingMode;
@property(nullable, copy, nonatomic) NSString *utiType;
@property(nonatomic) BOOL isVectorBased;
@end

NS_ASSUME_NONNULL_END

#endif
