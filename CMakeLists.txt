cmake_minimum_required(VERSION 3.21)
project(MewgenicsNative LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_ARCHITECTURES "arm64")
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0")

# L0 纯逻辑层：gpak 容器解析，零平台依赖
add_library(mew_core STATIC src/core/gpak.cpp src/core/swf.cpp)
target_link_libraries(mew_core PUBLIC z)
target_include_directories(mew_core PUBLIC src/core src/shim src/render)

# L2 视图层：AppKit 原生窗口
add_executable(MewgenicsNative MACOSX_BUNDLE src/ui/main.mm src/render/swfrender.mm)
target_link_libraries(MewgenicsNative PRIVATE mew_core "-framework Cocoa" "-framework ImageIO" "-framework CoreServices")

set_target_properties(MewgenicsNative PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "MewgenicsNative"
    MACOSX_BUNDLE_GUI_IDENTIFIER "local.mewgenics.native"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.1.0"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
)
