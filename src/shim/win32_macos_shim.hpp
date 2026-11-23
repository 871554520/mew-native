// 手册第 4 节模板：Win32 → macOS 轻量兼容层
// Mewgenics 用到的 Win32 面：文件路径/编码、计时、线程、用户目录。
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <filesystem>
#include <string>
#include <thread>

using BYTE   = uint8_t;
using WORD   = uint16_t;
using DWORD  = uint32_t;
using QWORD  = uint64_t;
#ifndef OBJC_BOOL_DEFINED
using BOOL   = int;   // ObjC++ 下 BOOL 已被 objc.h 定义成 bool，必须让位
#endif
using HANDLE = void*;
using LPSTR  = char*;
using LPCSTR = const char*;

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

namespace winshim {

inline uint64_t GetTickCount64() {
    using namespace std::chrono;
    return static_cast<uint64_t>(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
}

inline void SleepMs(DWORD ms) { std::this_thread::sleep_for(std::chrono::milliseconds(ms)); }

inline std::string Utf16ToUtf8(const uint16_t* src, size_t len = static_cast<size_t>(-1)) {
    if (!src) return {};
    std::string out;
    for (size_t i = 0; i < len && src[i] != 0; ++i) {
        uint32_t cp = src[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && (i + 1 < len) && src[i + 1] >= 0xDC00 && src[i + 1] <= 0xDFFF) {
            cp = 0x10000 + (((cp - 0xD800) << 10) | (src[++i] - 0xDC00));
        }
        if (cp < 0x80) {
            out.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
    return out;
}

inline std::filesystem::path AppDataDir(const std::string& appName) {
    const char* home = std::getenv("HOME");
    std::filesystem::path base = home ? std::filesystem::path(home) : std::filesystem::current_path();
    auto dir = base / "Library" / "Application Support" / appName;
    std::filesystem::create_directories(dir);
    return dir;
}

inline std::string NormalizePath(std::string winPath) {
    for (char& c : winPath) if (c == '\\') c = '/';
    return winPath;
}

} // namespace winshim
