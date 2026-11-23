#include "avm1.hpp"
#include <cmath>
#include <cstdio>
#include <sstream>

namespace avm1 {

struct Value::Func {
    std::vector<uint8_t> code;
    std::vector<std::string> params;
    std::string name;
};

double Value::toNumber() const {
    switch (type) {
        case Number: return num;
        case Bool: return num;
        case String: { char* end = nullptr; double d = std::strtod(str.c_str(), &end); return (end && end != str.c_str()) ? d : 0.0; }
        case Null: return 0.0;
        default: return 0.0;
    }
}

std::string Value::toString() const {
    switch (type) {
        case String: return str;
        case Number: { std::ostringstream os; if (num == (long long)num) os << (long long)num; else os << num; return os.str(); }
        case Bool: return num != 0 ? "1" : "0";
        case Null: return "null";
        case Undefined: return "undefined";
        case Function: return "[function " + (fn ? fn->name : "") + "]";
        case Object_: return "[object Object]";
    }
    return "";
}

bool Value::toBool() const {
    switch (type) {
        case Bool: case Number: return num != 0;
        case String: return !str.empty() && str != "0";
        case Null: case Undefined: return false;
        default: return true;
    }
}

Value VM::pop() {
    if (stack_.empty()) return Value::undefined();
    Value v = stack_.back();
    stack_.pop_back();
    return v;
}

void VM::push(const Value& v) { stack_.push_back(v); }

namespace {
inline uint16_t rd16(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
inline uint32_t rd32(const uint8_t* p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
inline double rdDouble(const uint8_t* p) { double d; __builtin_memcpy(&d, p, 8); return d; }
}

Value VM::callFunction(const Value& target, const std::vector<Value>& argv, int depth) {
    if (target.type != Value::Function || !target.fn) return Value::undefined();
    locals_.push_back({});
    for (size_t i = 0; i < target.fn->params.size() && i < argv.size(); ++i)
        locals_.back()[target.fn->params[i]] = argv[i];
    bool ok = exec(target.fn->code.data(), target.fn->code.size(), depth + 1);
    locals_.pop_back();
    if (!ok) error_ = "函数执行失败";
    return Value::undefined();
}

bool VM::run(const std::vector<uint8_t>& code) {
    if (timeline_ && timeline_->frameCount() <= 0) {
        // 仍允许无时间轴的纯计算脚本
    }
    return exec(code.data(), code.size(), 0);
}

bool VM::exec(const uint8_t* c, size_t n, int depth) {
    if (depth > 16) { error_ = "递归过深"; return false; }
    size_t pc = 0;
    while (pc < n) {
        uint8_t op = c[pc++];
        switch (op) {
            case 0x00: break; // End
            case 0x81: { // GotoFrame
                if (pc + 2 > n) return false;
                int f = rd16(c + pc); pc += 2;
                if (timeline_) timeline_->gotoFrame(f);
                break;
            }
            case 0x04: if (timeline_) timeline_->gotoFrame(timeline_->currentFrame() + 1); break;
            case 0x05: if (timeline_) timeline_->gotoFrame(timeline_->currentFrame() - 1); break;
            case 0x06: if (timeline_) timeline_->play(); break;
            case 0x07: if (timeline_) timeline_->stop(); break;
            case 0x26: { // Trace
                std::string s = pop().toString();
                traces.push_back(s);
                break;
            }
            case 0x17: pop(); break; // Pop
            case 0x18: { Value v = pop(); push(Value::number((double)(long long)v.toNumber())); break; } // ToInteger
            case 0x0F: { Value v = pop(); push(Value::boolean(!v.toBool())); break; } // Not
            case 0x10: { Value a = pop(), b = pop(); push(Value::boolean(a.toBool() && b.toBool())); break; }
            case 0x11: { Value a = pop(), b = pop(); push(Value::boolean(a.toBool() || b.toBool())); break; }
            case 0x0A: { Value a = pop(), b = pop(); push(Value::number(b.toNumber() + a.toNumber())); break; }
            case 0x0B: { Value a = pop(), b = pop(); push(Value::number(b.toNumber() - a.toNumber())); break; }
            case 0x0C: { Value a = pop(), b = pop(); push(Value::number(b.toNumber() * a.toNumber())); break; }
            case 0x0D: { Value a = pop(), b = pop(); push(Value::number(a.toNumber() != 0 ? b.toNumber() / a.toNumber() : 0)); break; }
            case 0x0E: { Value a = pop(), b = pop(); push(Value::number(std::fmod(b.toNumber(), a.toNumber()))); break; }
            case 0x21: { Value a = pop(), b = pop(); push(Value::string(b.toString() + a.toString())); break; } // StringAdd
            case 0x13: { Value a = pop(), b = pop(); push(Value::boolean(b.toString() == a.toString())); break; }
            case 0x47: { Value a = pop(), b = pop(); push(Value::boolean(b.toNumber() > a.toNumber())); break; } // Greater
            case 0x48: { Value a = pop(), b = pop(); push(Value::boolean(b.toNumber() < a.toNumber())); break; } // Less
            case 0x2A: { Value a = pop(), b = pop(); push(Value::boolean(b.toString() < a.toString())); break; }
            case 0x14: { Value a = pop(); push(Value::number((double)a.toString().size())); break; } // StringLength
            case 0x15: { // StringExtract
                Value cnt = pop(), start = pop(), str = pop();
                std::string s = str.toString();
                int st = (int)start.toNumber() - 1, len = (int)cnt.toNumber();
                if (st < 0) st = 0;
                if (len < 0 || st + len > (int)s.size()) len = (int)s.size() - st;
                push(Value::string(st <= (int)s.size() ? s.substr(st, len) : ""));
                break;
            }
            case 0x1C: { Value name = pop(); auto it = globals_.find(name.toString()); push(it != globals_.end() ? it->second : Value::undefined()); break; }
            case 0x1D: { Value val = pop(), name = pop(); globals_[name.toString()] = val; break; }
            case 0x3C: { Value val = pop(), name = pop(); if (!locals_.empty()) locals_.back()[name.toString()] = val; else globals_[name.toString()] = val; break; }
            case 0x3A: case 0x3B: { Value name = pop(); globals_.erase(name.toString()); break; }
            case 0x9D: { // If
                if (pc + 2 > n) return false;
                int16_t off = (int16_t)rd16(c + pc); pc += 2;
                Value cond = pop();
                if (cond.toBool()) pc += (size_t)off;
                break;
            }
            case 0x99: { // Jump
                if (pc + 2 > n) return false;
                int16_t off = (int16_t)rd16(c + pc); pc += 2;
                pc += (size_t)off;
                break;
            }
            case 0x9A: { Value target = pop(), url = pop(); (void)target; (void)url; break; } // GetURL
            case 0x9B: { // DefineFunction（名字与参数是 NUL 结尾的 STRING）
                auto readStr = [&](void) -> std::string {
                    std::string out;
                    while (pc < n && c[pc] != 0) out.push_back((char)c[pc++]);
                    if (pc < n) pc++;
                    return out;
                };
                auto fn = std::make_shared<Value::Func>();
                fn->name = readStr();
                if (pc + 2 > n) return false;
                int nparams = rd16(c + pc); pc += 2;
                for (int i = 0; i < nparams; ++i) fn->params.push_back(readStr());
                if (pc + 2 > n) return false;
                int codelen = rd16(c + pc); pc += 2;
                if (pc + codelen > n) return false;
                fn->code.assign(c + pc, c + pc + codelen);
                pc += codelen;
                Value fv; fv.type = Value::Function; fv.fn = fn;
                globals_[fn->name] = fv;
                push(fv);
                break;
            }
            case 0x4E: { // GetMember
                Value nameV = pop(), objV = pop();
                if (objV.type == Value::Object_ && objV.obj) {
                    auto it = objV.obj->props.find(nameV.toString());
                    push(it != objV.obj->props.end() ? it->second : Value::undefined());
                } else if (objV.type == Value::Undefined) {
                    auto it = globals_.find(nameV.toString());
                    push(it != globals_.end() ? it->second : Value::undefined());
                } else push(Value::undefined());
                break;
            }
            case 0x4F: { // SetMember(pop value, name, obj)
                Value val = pop(), nameV = pop(), objV = pop();
                auto target = objV;
                if (target.type != Value::Object_) target = Value::object();
                target.obj->props[nameV.toString()] = val;
                break;
            }
            case 0x40: { // NewObject
                Value nameV = pop();
                if (pc + 2 > n) return false;
                int argc = rd16(c + pc); pc += 2;
                for (int i = 0; i < argc * 2; ++i) pop();
                (void)nameV;
                push(Value::object());
                break;
            }
            case 0x4C: { // CallMethod
                Value methodV = pop(), objV = pop();
                if (pc + 2 > n) return false;
                int argc = rd16(c + pc); pc += 2;
                std::vector<Value> argv(argc);
                for (int i = argc - 1; i >= 0; --i) argv[i] = pop();
                Value fnV = Value::undefined();
                if (objV.type == Value::Object_ && objV.obj) {
                    auto it = objV.obj->props.find(methodV.toString());
                    if (it != objV.obj->props.end()) fnV = it->second;
                }
                if (fnV.type != Value::Function) {
                    auto it = globals_.find(methodV.toString());
                    if (it != globals_.end()) fnV = it->second;
                }
                callFunction(fnV, argv, depth);
                break;
            }
            case 0x8E: { // DefineFunction2
                auto readStr = [&](void) -> std::string {
                    std::string out;
                    while (pc < n && c[pc] != 0) out.push_back((char)c[pc++]);
                    if (pc < n) pc++;
                    return out;
                };
                auto fn = std::make_shared<Value::Func>();
                fn->name = readStr();
                if (pc + 2 > n) return false;
                int nparams = rd16(c + pc); pc += 2;
                uint8_t regCount = pc < n ? c[pc++] : 0;
                for (int i = 0; i < 8; ++i) { if (pc >= n) break; uint8_t flags = c[pc++]; (void)flags; }
                (void)regCount;
                for (int i = 0; i < nparams; ++i) fn->params.push_back(readStr());
                if (pc + 2 > n) return false;
                int codelen = rd16(c + pc); pc += 2;
                if (pc + codelen > n) return false;
                fn->code.assign(c + pc, c + pc + codelen);
                pc += codelen;
                Value fv; fv.type = Value::Function; fv.fn = fn;
                globals_[fn->name] = fv;
                push(fv);
                break;
            }
            case 0x3D: { // CallFunction
                Value nameV = pop();
                if (pc + 2 > n) return false;
                int nargs = rd16(c + pc); pc += 2;
                std::vector<Value> argv(nargs);
                for (int i = nargs - 1; i >= 0; --i) argv[i] = pop();
                Value target = nameV;
                if (nameV.type != Value::Function) {
                    auto it = globals_.find(nameV.toString());
                    if (it != globals_.end()) target = it->second;
                }
                Value ret = callFunction(target, argv, depth);
                (void)ret;
                break;
            }
            case 0x3E: return true; // Return
            case 0x88: { // ConstantPool
                if (pc + 2 > n) return false;
                int cnt = rd16(c + pc); pc += 2;
                pool_.clear();
                for (int i = 0; i < cnt; ++i) {
                    if (pc >= n) break;
                    uint8_t len = c[pc++];
                    pool_.push_back(std::string((const char*)c + pc, len));
                    pc += len;
                }
                break;
            }
            case 0x96: { // Push
                if (pc >= n) return false;
                uint8_t types = c[pc++];
                for (int i = 0; i < 10; ++i) {
                    if (!(types & (1 << i))) continue;
                    switch (i) {
                        case 0: {
                            if (pc + 2 > n) return false;
                            uint16_t len = rd16(c + pc); pc += 2;
                            if (pc + len > n) return false;
                            std::string sv((const char*)c + pc, len); pc += len;
                            while (!sv.empty() && sv.back() == '\0') sv.pop_back();
                            push(Value::string(sv));
                            break;
                        }
                        case 1: { float f = 0; __builtin_memcpy(&f, c + pc, 4); pc += 4; push(Value::number(f)); break; }
                        case 2: push(Value::null()); break;
                        case 3: push(Value::undefined()); break;
                        case 4: { uint8_t r = c[pc++]; (void)r; push(Value::undefined()); break; }
                        case 5: push(Value::boolean(c[pc++] != 0)); break;
                        case 6: { double d = rdDouble(c + pc); pc += 8; push(Value::number(d)); break; }
                        case 7: { int32_t v = (int32_t)rd32(c + pc); pc += 4; push(Value::number(v)); break; }
                        case 8: { uint8_t idx = c[pc++]; push(Value::string(idx < pool_.size() ? pool_[idx] : "")); break; }
                        case 9: { uint16_t idx = rd16(c + pc); pc += 2; push(Value::string(idx < pool_.size() ? pool_[idx] : "")); break; }
                    }
                }
                break;
            }
            default:
                error_ = "未实现指令 0x" + std::to_string((int)op);
                return false;
        }
    }
    return true;
}
} // namespace avm1
