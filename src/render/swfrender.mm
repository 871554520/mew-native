#include "swfrender.hpp"
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <cmath>
#include <map>
#include <vector>
#include <algorithm>

namespace mewrender {

static std::vector<DisplayItem> displayListFrom(const std::vector<swf::Frame>& frames, int frameIndex) {
    std::map<int, DisplayItem> list;
    int last = std::min(frameIndex, (int)frames.size() - 1);
    for (int f = 0; f <= last; ++f) {
        for (const auto& op : frames[f].ops) {
            if (op.remove) { list.erase(op.depth); continue; }
            DisplayItem it{op.depth, op.characterId, op.matrix};
            it.clipDepth = op.clipDepth; it.hasClip = op.hasClip;
            list[op.depth] = it;
        }
    }
    std::vector<DisplayItem> out;
    for (auto& kv : list) out.push_back(kv.second);
    return out;
}

std::vector<DisplayItem> buildDisplayList(const swf::Movie& mv, int frameIndex) {
    return displayListFrom(mv.frames, frameIndex);
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

static void addShapePath(CGContextRef ctx, const swf::Shape& sh, const swf::ShapePath& p) {
    if (p.pts.size() < 2) return;
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, p.pts[0].first, p.pts[0].second);
    for (size_t i = 1; i < p.pts.size(); ++i)
        CGContextAddLineToPoint(ctx, p.pts[i].first, p.pts[i].second);
    CGContextClosePath(ctx);
}

static void fillPath(CGContextRef ctx, const swf::Shape& sh, const swf::ShapePath& p) {
    const swf::FillStyle* fs = nullptr;
    if (p.fill0 >= 0 && p.fill0 < (int)sh.fills.size()) fs = &sh.fills[p.fill0];
    if (!fs) { CGContextSetRGBFillColor(ctx, 0.55, 0.55, 0.55, 1.0); return; }

    switch (fs->kind) {
        case swf::FillStyle::Solid:
            CGContextSetRGBFillColor(ctx, fs->r/255.0, fs->g/255.0, fs->b/255.0, fs->a/255.0);
            break;
        case swf::FillStyle::LinearGradient:
        case swf::FillStyle::RadialGradient: {
            size_t n = fs->stops.size();
            if (n < 2) { CGContextSetRGBFillColor(ctx, 0.5,0.5,0.5,1); break; }
            std::vector<CGFloat> comps, locs;
            for (auto& s : fs->stops) {
                comps.push_back(s.r/255.0); comps.push_back(s.g/255.0);
                comps.push_back(s.b/255.0); comps.push_back(s.a/255.0);
                locs.push_back(s.ratio/255.0);
            }
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGGradientRef grad = CGGradientCreateWithColorComponents(cs, comps.data(), locs.data(), n);
            CGColorSpaceRelease(cs);
            if (!grad) break;
            double ang = std::atan2(fs->matrix.b, fs->matrix.a);
            double len = 400;
            CGPoint start = CGPointMake(fs->matrix.tx, fs->matrix.ty);
            CGPoint end = CGPointMake(start.x + std::cos(ang) * len, start.y + std::sin(ang) * len);
            CGContextSaveGState(ctx);
            CGContextClip(ctx);
            if (fs->kind == swf::FillStyle::LinearGradient)
                CGContextDrawLinearGradient(ctx, grad, start, end, 0);
            else {
                double r = std::hypot(end.x - start.x, end.y - start.y);
                CGContextDrawRadialGradient(ctx, grad, start, 0, start, r, 0);
            }
            CGContextRestoreGState(ctx);
            CGGradientRelease(grad);
            return;
        }
        default: {
            // 位图填充：用容器里的位图平铺到路径范围（简化为中心贴图）
            CGContextSetRGBFillColor(ctx, 0.45, 0.45, 0.5, 1.0);
            break;
        }
    }
}

static void drawCharacter(CGContextRef ctx, const swf::Movie& mv, int characterId,
                          int frameIndex, int depthLimit);

static void drawFrameList(CGContextRef ctx, const swf::Movie& mv,
                          const std::vector<swf::Frame>& frames, int frameIndex, int depthLimit) {
    auto list = displayListFrom(frames, frameIndex);
    for (const auto& item : list) {
        CGContextSaveGState(ctx);
        CGAffineTransform t = CGAffineTransformMake(item.matrix.a, item.matrix.b,
                                                    item.matrix.c, item.matrix.d,
                                                    item.matrix.tx, item.matrix.ty);
        CGContextConcatCTM(ctx, t);

        if (item.hasClip) {
            // 作为遮罩：把它的形状设为裁剪区
            auto shIt = mv.shapes.find(item.characterId);
            if (shIt != mv.shapes.end()) {
                CGContextBeginPath(ctx);
                for (const auto& p : shIt->second.paths) {
                    if (p.pts.size() < 2) continue;
                    CGContextMoveToPoint(ctx, p.pts[0].first, p.pts[0].second);
                    for (size_t i = 1; i < p.pts.size(); ++i)
                        CGContextAddLineToPoint(ctx, p.pts[i].first, p.pts[i].second);
                    CGContextClosePath(ctx);
                }
                CGContextClip(ctx);
            }
        } else {
            drawCharacter(ctx, mv, item.characterId, frameIndex, depthLimit);
        }
        CGContextRestoreGState(ctx);
    }
}

static void drawCharacter(CGContextRef ctx, const swf::Movie& mv, int characterId,
                          int frameIndex, int depthLimit) {
    if (auto shIt = mv.shapes.find(characterId); shIt != mv.shapes.end()) {
        const swf::Shape& sh = shIt->second;
        for (const auto& path : sh.paths) {
            addShapePath(ctx, sh, path);
            fillPath(ctx, sh, path);
            CGContextFillPath(ctx);
        }
        return;
    }
    if (auto bmIt = mv.bitmaps.find(characterId); bmIt != mv.bitmaps.end()) {
        CGImageRef img = imageFromBitmap(bmIt->second);
        if (img) {
            double iw = CGImageGetWidth(img), ih = CGImageGetHeight(img);
            CGContextDrawImage(ctx, CGRectMake(0, 0, iw, ih), img);
            CGImageRelease(img);
        }
        return;
    }
    if (auto spIt = mv.sprites.find(characterId); spIt != mv.sprites.end()) {
        if (depthLimit <= 0) return;
        drawFrameList(ctx, mv, spIt->second.frames, frameIndex, depthLimit - 1);
    }
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

    double br = ((mv.backgroundColor >> 16) & 0xFF) / 255.0;
    double bg = ((mv.backgroundColor >> 8) & 0xFF) / 255.0;
    double bb = (mv.backgroundColor & 0xFF) / 255.0;
    CGContextSetRGBFillColor(ctx, br, bg, bb, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, pw, ph));

    CGContextTranslateCTM(ctx, 0, ph);
    CGContextScaleCTM(ctx, scale, -scale);
    CGContextTranslateCTM(ctx, -mv.frameSize.x0, -mv.frameSize.y0);

    drawFrameList(ctx, mv, mv.frames, frameIndex, 8);

    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return out;
}

} // namespace mewrender
