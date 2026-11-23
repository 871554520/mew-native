// SWF 渲染（L2）：显示列表合成 + CoreGraphics 绘制
#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <map>
#include <string>
#include "swf.hpp"

namespace mewrender {

struct DisplayItem { int depth; int characterId; swf::Matrix matrix; int clipDepth=0; bool hasClip=false; };

// 计算某帧的显示列表（从第 0 帧累加到 frameIndex）
std::vector<DisplayItem> buildDisplayList(const swf::Movie& mv, int frameIndex);

// 把某帧渲染成位图（逻辑坐标 1 单位 = 1 twip，输出按 scale 缩放）
CGImageRef renderFrame(const swf::Movie& mv, int frameIndex, double scale);

} // namespace mewrender
