// AVM1 解释器自检：手工拼字节码，验证算术/变量/跳转/函数
#include "avm1.hpp"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

using Bytes = std::vector<uint8_t>;

static void u16(Bytes& b, int v) { b.push_back(v & 0xFF); b.push_back((v >> 8) & 0xFF); }
static void str(Bytes& b, const std::string& s) { u16(b, (int)s.size()); b.insert(b.end(), s.begin(), s.end()); }
static void pushStr(Bytes& b, const std::string& s) { b.push_back(0x96); b.push_back(0x01); str(b, s); }
static void pushInt(Bytes& b, int v) { b.push_back(0x96); b.push_back(0x80); b.push_back(v & 0xFF); b.push_back((v>>8)&0xFF); b.push_back((v>>16)&0xFF); b.push_back((v>>24)&0xFF); }
static void trace(Bytes& b) { b.push_back(0x26); }

struct FakeTimeline : avm1::Timeline {
    int frame = 0, count = 10; bool playing = true;
    void gotoFrame(int f) override { frame = f < 0 ? 0 : (f >= count ? count - 1 : f); }
    void play() override { playing = true; }
    void stop() override { playing = false; }
    int currentFrame() override { return frame; }
    int frameCount() override { return count; }
};

int main() {
    int fails = 0;
    std::string lastErr;
    auto check = [&](const char* what, bool ok) {
        printf("%s %s%s%s\n", ok ? "PASS" : "FAIL", what,
               (!ok && !lastErr.empty()) ? "  <- " : "", (!ok && !lastErr.empty()) ? lastErr.c_str() : "");
        if (!ok) fails++;
    };

    {   // 字符串 + 算术
        Bytes code;
        pushStr(code, "hello "); pushStr(code, "avm1"); code.push_back(0x21); trace(code);
        pushInt(code, 7); pushInt(code, 5); code.push_back(0x0C); trace(code);
        avm1::VM vm;
        bool ok = vm.run(code); lastErr = vm.lastError();
        check("字符串拼接", ok && vm.traces.size() == 2 && vm.traces[0] == "hello avm1");
        check("乘法 7*5=35", ok && vm.traces.size() == 2 && vm.traces[1] == "35");
    }

    {   // 变量 + 循环（i 从 0 加到 3）
        Bytes code;
        // i = 0
        pushStr(code, "i"); pushInt(code, 0); code.push_back(0x1D);
        // loop:
        size_t loopStart = code.size();
        pushStr(code, "i"); code.push_back(0x1C);           // get i
        pushInt(code, 2); code.push_back(0x47);             // i > 2
        code.push_back(0x9D); u16(code, 0);                 // If -> 跳出
        size_t jumpPos = code.size() - 2;
        // i = i + 1
        pushStr(code, "i"); pushStr(code, "i"); code.push_back(0x1C); pushInt(code, 1); code.push_back(0x0A); code.push_back(0x1D);
        // goto loop
        code.push_back(0x99);
        int back = (int)(loopStart - (code.size() + 2));
        u16(code, back & 0xFFFF);
        // exit: trace i
        size_t exitPos = code.size();
        int fwd = (int)(exitPos - (jumpPos + 2));
        code[jumpPos] = fwd & 0xFF; code[jumpPos+1] = (fwd >> 8) & 0xFF;
        pushStr(code, "i"); code.push_back(0x1C); trace(code);

        avm1::VM vm;
        bool ok = vm.run(code); lastErr = vm.lastError();
        check("循环 i=3", ok && !vm.traces.empty() && vm.traces.back() == "3");
    }

    {   // 时间轴控制
        FakeTimeline tl;
        Bytes code;
        pushInt(code, 4);
        code.push_back(0x81); u16(code, 4);   // GotoFrame 4
        code.push_back(0x07);                  // Stop
        avm1::VM vm; vm.setTimeline(&tl);
        bool ok = vm.run(code); lastErr = vm.lastError();
        check("GotoFrame+Stop", ok && tl.frame == 4 && !tl.playing);
    }

    {   // 函数定义与调用
        Bytes body;
        pushStr(body, "x"); body.push_back(0x1C); pushInt(body, 2); body.push_back(0x0C); // x*2
        Bytes code;
        code.push_back(0x9B);
        for (char ch : std::string("dbl")) code.push_back((uint8_t)ch);
        code.push_back(0);
        u16(code, 0);                                // 0 个参数
        u16(code, (int)body.size()); code.insert(code.end(), body.begin(), body.end());
        code.push_back(0x17);                        // 弹出函数值
        pushStr(code, "dbl"); u16(code, 0); code.push_back(0x3D); // CallFunction "dbl"
        avm1::VM vm; vm.setGlobal("x", avm1::Value::number(21));
        bool ok = vm.run(code); lastErr = vm.lastError();
        printf("  globals.dbl=%s traces=%zu\n",
               vm.globals().count("dbl") ? "yes" : "no", vm.traces.size());
        check("DefineFunction/Call", ok);
    }

    printf(fails == 0 ? "ALL PASS\n" : "FAILURES %d\n", fails);
    return fails == 0 ? 0 : 1;
}
