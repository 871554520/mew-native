// L2 视图层：原生 AppKit 窗口，读取 resources.gpak 并预览贴图
#import <Cocoa/Cocoa.h>
#include <ImageIO/ImageIO.h>
#include <CoreServices/CoreServices.h>
#include <string>
#include <vector>
#include <map>
#include "gpak.hpp"
#include "win32_macos_shim.hpp"

static NSString* nsstr(const std::string& s) {
    return [NSString stringWithUTF8String:s.c_str()] ?: @"?";
}

@interface MewDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow* window;
@property (strong) NSTextField* info;
@property (strong) NSImageView* preview;
@end

@implementation MewDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)note {
    NSRect frame = NSMakeRect(0, 0, 980, 640);
    self.window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    [self.window setTitle:@"Mewgenics Native (macOS arm64)"];
    [self.window center];

    NSView* content = self.window.contentView;
    self.info = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 470, 940, 150)];
    [self.info setEditable:NO]; [self.info setBezeled:NO]; [self.info setDrawsBackground:NO];
    [self.info setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    [content addSubview:self.info];

    self.preview = [[NSImageView alloc] initWithFrame:NSMakeRect(20, 20, 940, 440)];
    [self.preview setImageScaling:NSImageScaleProportionallyUpOrDown];
    [content addSubview:self.preview];

    [self loadPack];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)loadPack {
    // 游戏目录：app 同级的 Mewgenics/，或 ~/Documents/Mewgenics/
    std::vector<std::string> cands;
    NSString* exeDir = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    cands.push_back(std::string([exeDir UTF8String]) + "/Mewgenics/resources.gpak");
    const char* home = std::getenv("HOME");
    if (home) cands.push_back(std::string(home) + "/Documents/Mewgenics/resources.gpak");
    cands.push_back("Mewgenics/resources.gpak");
    cands.push_back("resources.gpak");

    mew::Gpak pack;
    std::string used;
    for (auto& c : cands) if (pack.open(c)) { used = c; break; }
    if (used.empty()) {
        [self.info setStringValue:@"没找到 resources.gpak\n把它放到 ~/Documents/Mewgenics/resources.gpak"];
        return;
    }

    std::map<std::string,int> byExt;
    for (auto& e : pack.entries()) {
        auto dot = e.name.find_last_of('.');
        std::string ext = dot == std::string::npos ? "(none)" : e.name.substr(dot);
        byExt[ext]++;
    }
    std::string report = "容器：" + used + "\n";
    report += "条目：" + std::to_string(pack.entries().size()) + "   索引结束于偏移 " + std::to_string(pack.indexEnd()) + "\n";
    report += "按类型：";
    for (auto& kv : byExt) report += kv.first + "=" + std::to_string(kv.second) + "  ";
    report += "\n构建：arm64 Mach-O / AppKit 原生窗口 / gpak 直读（无 Wine）";

    // 预览一张贴图
    if (auto* e = pack.find("textures/eyestrip1.png")) {
        std::vector<uint8_t> data;
        if (pack.read(*e, data)) {
            NSData* nsd = [NSData dataWithBytes:data.data() length:data.size()];
            CGImageSourceRef src = CGImageSourceCreateWithData((CFDataRef)nsd, NULL);
            if (src) {
                CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
                if (img) { [self.preview setImage:[[NSImage alloc] initWithCGImage:img size:NSZeroSize]]; CGImageRelease(img); }
                CFRelease(src);
            }
        }
    }
    [self.info setStringValue:nsstr(report)];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender { return YES; }
@end

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        MewDelegate* del = [[MewDelegate alloc] init];
        [app setDelegate:del];
        [app run];
    }
    return 0;
}
