cmake_minimum_required(VERSION 3.14)
project(browser_bridge LANGUAGES CXX)

# cccode-browser-host.exe, the browsers' native messaging host (host.cpp).
# It goes beside cccode.exe with vip.cchub.cccode.browser.json, the manifest
# the browsers find it by: the installer's keys point there (see
# tool/cccode.iss), and its "path", relative, is the host beside it.
add_executable(cccode-browser-host "host.cpp")
apply_standard_settings(cccode-browser-host)
target_compile_options(cccode-browser-host PRIVATE /utf-8)
target_compile_definitions(cccode-browser-host PRIVATE
  "NOMINMAX" "WIN32_LEAN_AND_MEAN")
target_link_libraries(cccode-browser-host PRIVATE "ws2_32.lib")
