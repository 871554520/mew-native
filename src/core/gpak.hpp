// resources.gpak 容器读取（L0 纯逻辑层：零平台依赖）
// 格式：u32 条目数 + 每条(u16 名称长度, UTF-8 名称, u32 大小)，索引之后数据未压缩顺序排列
#pragma once
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace mew {

struct GpakEntry {
    std::string name;
    uint64_t offset = 0;
    uint32_t size = 0;
};

class Gpak {
public:
    bool open(const std::string& path);
    void close();
    const std::vector<GpakEntry>& entries() const { return entries_; }
    const GpakEntry* find(const std::string& name) const;
    bool read(const GpakEntry& e, std::vector<uint8_t>& out) const;
    uint64_t indexEnd() const { return indexEnd_; }
    FILE* handle() const { return fp_; }

private:
    FILE* fp_ = nullptr;
    std::vector<GpakEntry> entries_;
    uint64_t indexEnd_ = 0;
};

} // namespace mew
