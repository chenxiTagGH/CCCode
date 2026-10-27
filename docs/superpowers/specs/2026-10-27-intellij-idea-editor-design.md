# IntelliJ IDEA 外部编辑器支持设计

## 目标

在 CCCode 的“打开项目”编辑器菜单中加入 IntelliJ IDEA，支持 macOS 和 Windows；Linux 不新增该菜单项。用户选择后，项目文件夹应使用 IntelliJ IDEA 打开，并沿用现有编辑器偏好持久化机制。

## 方案

复用现有 `Editor` 枚举和平台启动器，不增加新的设置页或路径配置：

- 新增 `Editor.intellijIdea`。
- macOS 使用 `open -a "IntelliJ IDEA" <path>`。
- Windows 使用现有外部编辑器启动通道，调用 `idea <path>`。
- Linux 上该编辑器标记为不可用，因此不出现在菜单中。
- 未安装 IntelliJ IDEA 时沿用现有失败语义，不影响 CCCode 内置 IDE 和其他编辑器。

## 数据流

1. 用户在编辑器菜单选择 IntelliJ IDEA。
2. 现有 workspace/editor launcher 传递 `Editor.intellijIdea` 和项目路径。
3. 平台实现根据 `Editor` 的命令或应用名启动 IntelliJ IDEA。
4. 成功或失败结果沿用现有菜单和调用方逻辑。
5. 现有 `editor` 偏好键保存和恢复 `intellijIdea`。

## 测试

只增加与修改相关的测试：

- IntelliJ IDEA 在 macOS 和 Windows 可用，在 Linux 不可用。
- macOS 使用 `IntelliJ IDEA` 应用名。
- Windows 使用 `idea` 命令。
- 编辑器偏好能够保存并恢复 IntelliJ IDEA。
- 现有 VS Code、Cursor、Zed、Xcode、Fast IDE 等行为保持不变。

## 范围边界

- 不支持 Linux 菜单项。
- 不实现多个 IntelliJ 发行版的动态探测。
- 不增加用户手动配置可执行文件路径的设置。
- 不修改 CCCode 内置 IDE 的实现。
