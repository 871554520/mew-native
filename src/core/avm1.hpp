// AVM1（ActionScript 1/2）字节码解释器（L0，零平台依赖）
#pragma once
#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace avm1 {

struct Value;
struct Object {
    std::map<std::string, Value> props;
};

struct Value {
    enum Type { Undefined, Null, Number, String, Bool, Function, Object_ } type = Undefined;
    double num = 0;
    std::string str;
    struct Func;
    std::shared_ptr<Func> fn;
    std::shared_ptr<Object> obj;

    static Value number(double v) { Value x; x.type = Number; x.num = v; return x; }
    static Value string(const std::string& s) { Value x; x.type = String; x.str = s; return x; }
    static Value boolean(bool b) { Value x; x.type = Bool; x.num = b ? 1 : 0; return x; }
    static Value null() { Value x; x.type = Null; return x; }
    static Value object() { Value x; x.type = Object_; x.obj = std::make_shared<Object>(); return x; }
    static Value undefined() { return Value(); }

    double toNumber() const;
    std::string toString() const;
    bool toBool() const;
};

// 供脚本操控的时间轴（由渲染层实现）
class Timeline {
public:
    virtual ~Timeline() = default;
    virtual void gotoFrame(int frame) = 0;   // 0-based
    virtual void play() = 0;
    virtual void stop() = 0;
    virtual int currentFrame() = 0;
    virtual int frameCount() = 0;
};

class VM {
public:
    void setTimeline(Timeline* tl) { timeline_ = tl; }
    void setGlobal(const std::string& k, const Value& v) { globals_[k] = v; }
    const std::map<std::string, Value>& globals() const { return globals_; }

    // 执行一段 DoAction 字节码；返回 false 表示遇到非法指令中止
    bool run(const std::vector<uint8_t>& code);
    const std::string& lastError() const { return error_; }
    std::vector<std::string> traces;

private:
    bool exec(const uint8_t* code, size_t n, int depth);
    Value callFunction(const Value& target, const std::vector<Value>& argv, int depth);
    Value pop();
    void push(const Value& v);

    std::vector<Value> stack_;
    std::vector<Value> args_;
    std::map<std::string, Value> globals_;
    std::vector<std::map<std::string, Value>> locals_;
    std::vector<std::string> pool_;
    Timeline* timeline_ = nullptr;
    std::string error_;
};

} // namespace avm1
