#include "swfrender.hpp"
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <cmath>
#include <vector>
#include <algorithm>

namespace mewrender {

std::vector<DisplayItem> buildDisplayList(const swf::Movie& mv, int frameIndex) {
    std::map<int, DisplayItem> list;
    int last = std::min(frameIndex, (int)mv.frames.size() - 1);
    for (int f = 0; f <= last; ++f) {
        for (const auto& op : mv.frames[f].ops) {
            if (op.remove) { list.erase(op.depth); continue; }
            list[op.depth] = DisplayItem{op.depth, op.characterId, op.matrix};
        }
    }
    std::vector<DisplayItem> out;
    for (auto& kv : list) out.push_back(kv.second);
    return out;
}

static CGImageRef imageFromBitmap(const swf::Bitmap& b) {
    if (!b.jpeg.empty()) {
        CFDataRef data = CFDataCreate(nullptr, b.jpeg.data(), b.jpeg.size());
        CGImageSourceRef src = CGImageSourceCreateWithData(data, nullptr);
        CGImageRef img = src ? CGImageSourceCreateImageAtIndex(src, 0, nullptr) : nullptr;
        if (src) CFRelease(src);
        CFRelease(data);
        return img;
    }
    if (!b.rgba.empty() && b.width > 0 && b.height > 0) {
        size_t n = (size_t)b.width * b.height * 4;
        if (b.rgba.size() < n) return nullptr;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate((void*)b.rgba.data(), b.width, b.height, 8,
                                                 b.width * 4, cs,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGImageRef img = ctx ? CGBitmapContextCreateImage(ctx) : nullptr;
        if (ctx) CGContextRelease(ctx);
        CGColorSpaceRelease(cs);
        return img;
    }
    return nullptr;
}

CGImageRef renderFrame(const swf::Movie& mv, int frameIndex, double scale) {
    double w = mv.frameSize.x1 - mv.frameSize.x0;
    double h = mv.frameSize.y1 - mv.frameSize.y0;
    if (w <= 0 || h <= 0) { w = 550; h = 400; }
    size_t pw = (size_t)std::max(1.0, w * scale);
    size_t ph = (size_t)std::max(1.0, h * scale);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(nullptr, pw, ph, 8, pw * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) return nullptr;

    // 背景
    double br = ((mv.backgroundColor >> 16) & 0xFF) / 255.0;
    double bg = ((mv.backgroundColor >> 8) & 0xFF) / 255.0;
    double bb = (mv.backgroundColor & 0xFF) / 255.0;
    CGContextSetRGBFillColor(ctx, br, bg, bb, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, pw, ph));

    // 坐标：SWF 原点左上，y 向下；CG 原点左下
    CGContextTranslateCTM(ctx, 0, ph);
    CGContextScaleCTM(ctx, scale, -scale);
    CGContextTranslateCTM(ctx, -mv.frameSize.x0, -mv.frameSize.y0);

    for (const auto& item : buildDisplayList(mv, frameIndex)) {
        // 矩阵：a b c d tx ty
        CGAffineTransform t = CGAffineTransformMake(item.matrix.a, item.matrix.b,
                                                    item.matrix.c, item.matrix.d,
                                                    item.matrix.tx, item.matrix.ty);
        CGContextSaveGState(ctx);
        CGContextConcatCTM(ctx, t);

        auto shIt = mv.shapes.find(item.characterId);
        if (shIt != mv.shapes.end()) {
            const swf::Shape& sh = shIt->second;
            for (const auto& path : sh.paths) {
                if (path.pts.size() < 2) continue;
                CGMutablePathRef cgp = CGPathCreateMutable();
                CGPathMoveToPoint(cgp, nullptr, path.pts[0].first, path.pts[0].second);
                for (size_t i = 1; i < path.pts.size(); ++i)
                    CGPathAddLineToPoint(cgp, nullptr, path.pts[i].first, path.pts[i].second);
                CGPathCloseSubpath(cgp);
                const swf::FillStyle* fs = nullptr;
                if (path.fill0 >= 0 && path.fill0 < (int)sh.fills.size()) fs = &sh.fills[path.fill0];
                if (fs && fs->kind == swf::FillStyle::Solid) {
                    CGContextSetRGBFillColor(ctx, fs->r/255.0, fs->g/255.0, fs->b/255.0, fs->a/255.0);
                    CGContextAddPath(ctx, cgp);
                    CGContextFillPath(ctx);
                } else {
                    CGContextSetRGBFillColor(ctx, 0.6, 0.6, 0.6, 1.0);
                    CGContextAddPath(ctx, cgp);
                    CGContextFillPath(ctx);
                }
                CGPathRelease(cgp);
            }
        }

        auto bmIt = mv.bitmaps.find(item.characterId);
        if (bmIt != mv.bitmaps.end()) {
            CGImageRef img = imageFromBitmap(bmIt->second);
            if (img) {
                double iw = CGImageGetWidth(img), ih = CGImageGetHeight(img);
                CGContextDrawImage(ctx, CGRectMake(0, 0, iw, ih), img);
                CGImageRelease(img);
            }
        }
        CGContextRestoreGState(ctx);
    }

    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return out;
}

} // namespace mewrender
