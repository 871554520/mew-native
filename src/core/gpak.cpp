#include "gpak.hpp"
#include <cstring>

namespace mew {

static bool readU32(FILE* f, uint32_t& v) { return std::fread(&v, 4, 1, f) == 1; }
static bool readU16(FILE* f, uint16_t& v) { return std::fread(&v, 2, 1, f) == 1; }

bool Gpak::open(const std::string& path) {
    close();
    fp_ = std::fopen(path.c_str(), "rb");
    if (!fp_) return false;
    uint32_t count = 0;
    if (!readU32(fp_, count)) return false;
    entries_.reserve(count);
    uint64_t off = 4;
    for (uint32_t i = 0; i < count; ++i) {
        uint16_t nlen = 0;
        if (!readU16(fp_, nlen)) return false;
        std::string name(nlen, '\0');
        if (nlen && std::fread(&name[0], 1, nlen, fp_) != nlen) return false;
        uint32_t size = 0;
        if (!readU32(fp_, size)) return false;
        off += 2 + nlen + 4;
        entries_.push_back({std::move(name), 0, size});
    }
    indexEnd_ = off;
    uint64_t cur = indexEnd_;
    for (auto& e : entries_) { e.offset = cur; cur += e.size; }
    return true;
}

void Gpak::close() {
    if (fp_) { std::fclose(fp_); fp_ = nullptr; }
    entries_.clear(); indexEnd_ = 0;
}

const GpakEntry* Gpak::find(const std::string& name) const {
    for (const auto& e : entries_) if (e.name == name) return &e;
    return nullptr;
}

bool Gpak::read(const GpakEntry& e, std::vector<uint8_t>& out) const {
    if (!fp_) return false;
    out.resize(e.size);
    if (std::fseek(fp_, static_cast<long>(e.offset), SEEK_SET) != 0) return false;
    return e.size == 0 || std::fread(out.data(), 1, e.size, fp_) == e.size;
}

} // namespace mew
