// L2 视图：AppKit 窗口 —— 从 resources.gpak 里挑 SWF，逐帧渲染
#import <Cocoa/Cocoa.h>
#include <string>
#include <vector>
#include <algorithm>
#include <functional>
#include "gpak.hpp"
#include "swf.hpp"
#include "swfrender.hpp"
#include "avm1.hpp"

static NSString* S(const std::string& s) { return [NSString stringWithUTF8String:s.c_str()] ?: @"?"; }

class ViewportTimeline : public avm1::Timeline {
public:
    __weak NSObject* owner = nil;
    int frame = 0;
    bool playing = false;
    int count = 0;
    std::function<void(int)> onGoto;
    std::function<void(bool)> onPlay;
    void gotoFrame(int f) override { frame = f < 0 ? 0 : (count && f >= count ? count - 1 : f); if (onGoto) onGoto(frame); }
    void play() override { playing = true; if (onPlay) onPlay(true); }
    void stop() override { playing = false; if (onPlay) onPlay(false); }
    int currentFrame() override { return frame; }
    int frameCount() override { return count; }
};

@interface Viewer : NSObject <NSApplicationDelegate>
@property (strong) NSWindow* win;
@property (strong) NSTextField* info;
@property (strong) NSImageView* view;
@property (strong) NSSlider* slider;
@property (strong) NSPopUpButton* picker;
@property (strong) NSTextField* frameLabel;
@end

@implementation Viewer {
    mew::Gpak _pack;
    std::vector<std::string> _swfNames;
    swf::Movie _movie;
    int _frame;
    avm1::VM _vm;
    ViewportTimeline* _tl;
    NSTimer* _timer;
    BOOL _playing;
}

- (void)applicationDidFinishLaunching:(NSNotification*)n {
    NSRect f = NSMakeRect(0,0,1080,720);
    self.win = [[NSWindow alloc] initWithContentRect:f
        styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    [self.win setTitle:@"Mewgenics SWF Runtime (native arm64)"];
    [self.win center];
    NSView* c = self.win.contentView;

    self.picker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 668, 520, 28) pullsDown:NO];
    [self.picker setTarget:self]; [self.picker setAction:@selector(pickChanged:)];
    [c addSubview:self.picker];

    self.slider = [[NSSlider alloc] initWithFrame:NSMakeRect(560, 668, 380, 28)];
    [self.slider setTarget:self]; [self.slider setAction:@selector(frameChanged:)];
    [self.slider setMinValue:0]; [self.slider setMaxValue:1];
    [c addSubview:self.slider];

    self.frameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(952, 670, 110, 22)];
    [self.frameLabel setEditable:NO]; [self.frameLabel setBezeled:NO]; [self.frameLabel setDrawsBackground:NO];
    [c addSubview:self.frameLabel];

    self.view = [[NSImageView alloc] initWithFrame:NSMakeRect(20, 150, 1040, 500)];
    self.view.editable = NO;
    [self.view setImageScaling:NSImageScaleProportionallyUpOrDown];
    [c addSubview:self.view];

    self.info = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 1040, 120)];
    [self.info setEditable:NO]; [self.info setBezeled:NO]; [self.info setDrawsBackground:NO];
    [self.info setFont:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]];
    [c addSubview:self.info];

    [self loadPack];
    [self.win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0/24.0 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}

- (void)loadPack {
    std::vector<std::string> cands;
    NSString* exeDir = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    cands.push_back(std::string([exeDir UTF8String]) + "/Mewgenics/resources.gpak");
    const char* home = std::getenv("HOME");
    if (home) cands.push_back(std::string(home) + "/Documents/Mewgenics/resources.gpak");
    cands.push_back("Mewgenics/resources.gpak");
    cands.push_back("resources.gpak");
    std::string used;
    for (auto& p : cands) if (_pack.open(p)) { used = p; break; }
    if (used.empty()) {
        [self.info setStringValue:@"没找到 resources.gpak\n放到 ~/Documents/Mewgenics/resources.gpak 后重启"];
        return;
    }
    for (auto& e : _pack.entries())
        if (e.name.rfind("swfs/", 0) == 0 && e.size > 4096) _swfNames.push_back(e.name);
    std::sort(_swfNames.begin(), _swfNames.end());
    for (auto& n : _swfNames) [self.picker addItemWithTitle:S(n)];
    [self.info setStringValue:[NSString stringWithFormat:@"容器 %s  条目 %zu  SWF %zu",
                               used.c_str(), _pack.entries().size(), _swfNames.size()]];
    if (!_swfNames.empty()) [self loadSwf:_swfNames[0]];
}

- (void)runActionsForFrame:(int)f {
    if (f >= 0 && f < (int)_movie.frames.size()) {
        const auto& code = _movie.frames[f].actions;
        if (!code.empty()) {
            _vm.setTimeline(_tl);
            _vm.run(code);
            for (auto& t : _vm.traces) NSLog(@"[trace] %s", t.c_str());
            _frame = _tl->currentFrame();
        }
    }
}

- (void)tick:(NSTimer*)t {
    if (!_playing) return;
    int next = _frame + 1;
    if (next >= (int)_movie.frames.size()) next = 0;
    _frame = next;
    [self.slider setDoubleValue:_frame];
    [self runActionsForFrame:_frame];
    [self render];
}

- (void)loadSwf:(const std::string&)name {
    const mew::GpakEntry* e = _pack.find(name);
    if (!e) return;
    std::vector<uint8_t> data;
    if (!_pack.read(*e, data)) return;
    std::string err;
    if (!swf::parseMemory(data, _movie, &err)) {
        [self.info setStringValue:[NSString stringWithFormat:@"解析失败：%s", err.c_str()]];
        return;
    }
    _frame = 0;
    if (!_tl) {
        _tl = new ViewportTimeline();
        __weak Viewer* weakSelf = self;
        _tl->onGoto = [weakSelf](int f) {
            Viewer* s = weakSelf; if (!s) return;
            s->_frame = f; [s.slider setDoubleValue:f]; [s render];
        };
        _tl->onPlay = [weakSelf](bool p) {
            Viewer* s = weakSelf; if (!s) return;
            s->_playing = p;
        };
    }
    _tl->count = (int)_movie.frames.size();
    _tl->frame = 0;
    _playing = YES;
    _vm = avm1::VM();
    _vm.setTimeline(_tl);
    for (auto& a : _movie.initActions) _vm.run(a);
    [self.slider setMaxValue:std::max(1, (int)_movie.frames.size() - 1)];
    [self.slider setDoubleValue:0];
    [self render];
    NSMutableString* s = [NSMutableString string];
    [s appendFormat:@"%s\n", name.c_str()];
    [s appendFormat:@"帧 %zu  帧率 %.2f  声明 %d  背景 #%06X\n",
        _movie.frames.size(), _movie.frameRate, _movie.frameCount, _movie.backgroundColor];
    size_t sprites = _movie.sprites.size(), clip = 0;
    for (auto& f : _movie.frames) for (auto& op : f.ops) if (op.hasClip) clip++;
    [s appendFormat:@"形状 %zu  位图 %zu  精灵 %zu  按钮 %zu  遮罩 %zu  tag 种类 %zu\n",
        _movie.shapes.size(), _movie.bitmaps.size(), sprites, _movie.buttons.size(), clip, _movie.tagHistogram.size()];
    [self.info setStringValue:s];
}

- (void)render {
    if (_frame < 0) _frame = 0;
    CGImageRef img = mewrender::renderFrame(_movie, _frame, 1.0);
    if (!img) return;
    [self.view setImage:[[NSImage alloc] initWithCGImage:img size:NSZeroSize]];
    CGImageRelease(img);
    [self.frameLabel setStringValue:[NSString stringWithFormat:@"frame %d / %zu", _frame, _movie.frames.size()]];
}

- (void)pickChanged:(id)sender {
    NSInteger i = [self.picker indexOfSelectedItem];
    if (i >= 0 && i < (NSInteger)_swfNames.size()) [self loadSwf:_swfNames[i]];
}
- (void)frameChanged:(id)sender {
    _frame = (int)[self.slider doubleValue];
    if (_tl) { _tl->frame = _frame; }
    [self runActionsForFrame:_frame];
    [self render];
}
- (void)mouseDown:(NSEvent*)ev {
    // 视图 -> SWF 坐标（twips，y 向下）
    NSPoint p = [self.view convertPoint:[ev locationInWindow] fromView:nil];
    NSRect b = self.view.bounds;
    double w = _movie.frameSize.x1 - _movie.frameSize.x0;
    double h = _movie.frameSize.y1 - _movie.frameSize.y0;
    if (w <= 0 || h <= 0) return;
    double nx = p.x / b.size.width;
    double ny = 1.0 - (p.y / b.size.height);
    double mx = _movie.frameSize.x0 + nx * w;
    double my = _movie.frameSize.y0 + ny * h;

    bool fired = false;
    for (const auto& item : mewrender::buildDisplayList(_movie, _frame)) {
        auto bit = _movie.buttons.find(item.characterId);
        if (bit == _movie.buttons.end()) continue;
        const swf::Button& btn = bit->second;
        if (!swf::hitTestButton(_movie, btn, mx, my,
                                item.matrix.a, item.matrix.b, item.matrix.c, item.matrix.d,
                                item.matrix.tx, item.matrix.ty)) continue;
        for (const auto& act : btn.actions) {
            uint16_t cond = act.conditions;
            bool take = false;
            for (int bits = 0; bits < 4; ++bits) {
                int state = (cond >> (bits * 2)) & 3;
                if (state == 2 && bits == 3) take = true;   // Release
                if (state == 1) take = true;                 // 任一按下态
            }
            if (!take) continue;
            if (_tl) { _tl->frame = _frame; _vm.setTimeline(_tl); }
            _vm.run(act.code);
            for (auto& t : _vm.traces) NSLog(@"[trace] %s", t.c_str());
            _frame = _tl ? _tl->currentFrame() : _frame;
            [self.slider setDoubleValue:_frame];
            [self render];
            fired = true;
        }
        if (fired) break;
    }
    if (!fired) [self render];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)a { return YES; }
@end

int main(int argc, const char* argv[]) {
    if (argc >= 3 && std::string(argv[1]) == "--scan") {
        swf::Movie mv; std::string err;
        if (!swf::parse(argv[2], mv, &err)) { printf("ERR %s\n", err.c_str()); return 1; }
        printf("frames=%zu rate=%.2f shapes=%zu bitmaps=%zu tags=%zu\n",
               mv.frames.size(), mv.frameRate, mv.shapes.size(), mv.bitmaps.size(), mv.tagHistogram.size());
        size_t paths=0, fills=0, grads=0, spriteFrames=0;
        for (auto& kv : mv.shapes) {
            paths += kv.second.paths.size();
            for (auto& f : kv.second.fills) if (f.kind != swf::FillStyle::Solid && f.kind != swf::FillStyle::Bitmap) grads++;
            fills += kv.second.fills.size();
        }
        for (auto& kv : mv.sprites) spriteFrames += kv.second.frames.size();
        printf("paths=%zu fills=%zu gradients=%zu sprites=%zu spriteFrames=%zu bg=#%06X\n",
               paths, fills, grads, mv.sprites.size(), spriteFrames, mv.backgroundColor);
        return 0;
    }
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        Viewer* d = [[Viewer alloc] init];
        [app setDelegate:d];
        [app run];
    }
    return 0;
}
