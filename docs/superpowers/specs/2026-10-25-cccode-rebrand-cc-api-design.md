# CCCode 品牌重命名与 CC API 一键接入设计

## 1. 目标与范围

本次二开将 CCCode fork 定制为 CCCode，并在普通 CCCode 版本的“设置 → 模型”中内置 CC API 一键接入能力。

目标：

- 将用户可见和系统可识别的 CCCode 产品标识替换为 CCCode；
- 保留现有 Dart 包名 `cccode` 和 `package:baocode/...` 导入，不进行无收益的 Dart 包重命名；
- 不保留 CCCode 兼容层，不迁移旧 CCCode 数据，不继续注册 `cccode://`；
- 使用用户提供的 CC AI API Logo；
- 将 `https://api.cc-hub.vip` 作为内置 Provider；
- 点击 CC API 卡片后打开网页登录，登录成功后自动同步账户、API Key、模型列表，并设置默认模型；
- 保留手动添加其他 Provider 和外部推荐 Provider 的能力。

不在本次范围内：

- 重写 Claude Code 核心或模型代理协议；
- 增加新的 Gemini 协议枚举；
- 把 CC API 的模型名称硬编码到客户端；
- 修改 CC API 服务端；
- 将用户的 refresh token 或 API Key 写入普通配置文件、日志或 URL。

## 2. 品牌与标识策略

### 2.1 命名规则

用户可见和平台可识别的产品标识统一替换：

- `CCCode` → `CCCode`；
- `cccode` → `cccode`；
- 应用窗口标题、菜单、关于页、欢迎页、通知、错误提示、README、官网、构建产物、日志目录、数据目录、URL scheme 和 native method channel 名称均使用 CCCode 标识。

Dart 包名保持 `cccode`，因此以下内容不改：

- `pubspec.yaml` 的 package name；
- `package:baocode/...` 导入路径；
- 仅用于 Dart 包解析的测试导入。

旧 CCCode 标识不做运行时兼容：

- 不注册 `cccode://`；
- 新 scheme 为 `cccode://`；
- 不读取或迁移旧 CCCode 数据目录；
- 新版本使用独立的 CCCode 数据目录和系统标识。

平台应用标识使用 CCCode 专属 reverse-DNS 标识，默认采用 `vip.cchub.cccode`，各平台测试目标保留必要的 `.Runner`、`.Tests` 等后缀。

### 2.2 Logo

使用用户提供的 `/Users/tangchenxi/logos/cc-ai-api/final/cc-ai-api-logo.svg`，不重新绘制图形。

资源用途：

- `assets/branding/` 中的应用 Logo；
- 设置 → 模型中的 CC API 卡片 Logo；
- macOS、Windows、Linux、浏览器扩展所需的应用图标变体。

保留原 Logo 色值：`#0B132B`、`#18CDE2`、`#4A69FF`、`#FFBF3F`。生成桌面图标时保证透明边缘、正方形画布和小尺寸可辨识度。

## 3. CC API 连接架构

普通 CCCode 不复用渠道构建的 `ChannelGate` 启动流程，而是新增可复用的 CC API 连接器。连接器复用已有的登录窗口和 Sub2API API 适配器。

建议职责划分：

- `CcApiConnector`：管理连接状态、登录窗口、账户同步和 Provider 同步；
- `Sub2ApiAdapter`：继续负责 `/api/v1` refresh token、账户、Key、分组和登出接口；
- `ModelProviders`：继续负责 Provider 配置和 API Key 的系统钥匙串存储；
- CC API 卡片 Widget：展示状态并触发连接、重试、刷新操作；
- 现有 `listUpstreamModels`：根据实际 Provider 协议和返回数据获取模型。

Provider 固定信息：

- ID：`cc-api`；
- 名称：`CC API`；
- Base URL：`https://api.cc-hub.vip`；
- 首选协议：Anthropic；
- `disableNonessentialTraffic`：启用。

Anthropic 作为首选入口是因为 CCCode 的核心运行时通过 Claude Code 的 Anthropic 环境变量工作。OpenAI/Gemini 模型不在客户端写死名称，而由 CC API 的模型列表返回并进入现有模型映射流程；如果后续服务端对单个模型要求不同协议，再利用现有的模型级协议覆盖能力扩展。

## 4. 一键连接数据流

```text
设置 → 模型 → 点击 CC API
  → 打开内置 https://api.cc-hub.vip/login
  → 每秒读取登录窗口 localStorage.refresh_token
  → 关闭登录窗口
  → POST /api/v1/auth/refresh
  → GET /api/v1/auth/me
  → GET /api/v1/keys
  → 选择或创建 CCCode API Key
  → 获取完整 API Key
  → GET /v1/models
  → 解析并合并 ProviderModel
  → 保存 Provider 与默认模型
  → 卡片显示已连接
```

Key 选择顺序：

1. `cc-api` Provider 当前关联的 Key 仍然存在时继续使用；
2. 使用账户中名称为 `CCCode` 的 Key；
3. 使用账户返回的最新 Key；
4. 没有 Key 时创建名为 `CCCode` 的 Key；
5. 创建时优先使用 `anthropic` 分组，否则使用服务端返回的第一个分组。

模型列表以 CC API 实际响应为准，解析 `id`、`name`、`display_name`、上下文长度、输出类型等字段。合并时保留用户手动设置的启用状态，服务端不再返回的旧模型标记为 missing。默认模型优先选择名称包含 `sonnet` 或 `claude` 的可对话模型，否则选择第一个可对话模型。

## 5. 模型页交互

在现有外部推荐 Provider 卡片之前增加固定的 CC API 卡片。

状态：

- 未连接：显示“登录 CC API”；
- 连接中：显示加载状态并禁用重复点击；
- 已连接：显示“已连接 · N 个模型”；
- 需要重新登录：保留本地 Provider 和模型，显示重试入口；
- 刷新失败：保留旧模型，不清空可用配置。

成功后的 Provider 行显示 CC API、协议、`api.cc-hub.vip` 和模型数量。外部 iFruit、YMeng CC 等卡片仍按原逻辑打开站点，不改变其导入行为。

至少补齐中文和英文文案：CC API、Claude/GPT/Gemini 一键接入、登录 CC API、正在连接、已连接、刷新模型、需要重新登录、暂时无法连接。

## 6. 状态与安全

- 登录 refresh token 只存系统钥匙串；
- Provider API Key 继续使用现有 Provider SecretStore；
- Provider、模型和默认模型使用现有 settings 存储；
- 不把 token、Key、Cookie、完整请求头或登录窗口内容写入日志；
- 用户关闭登录窗口且未检测到 refresh token 时不修改配置；
- refresh 失败时清除失效 session，但保留旧 Provider 和模型，避免用户当前配置突然消失；
- 网络超时、模型列表失败和服务端空列表均不覆盖已存在的有效模型；
- 连接器不得在普通版本启动时自动弹出登录窗口。

## 7. 测试与验证

仅运行与本次变更相关的测试，不运行完整测试套件。

测试覆盖：

- `Sub2ApiAdapter`：refresh token 交换、401/403 登出、Key 列表、Key 创建、Key 解密和登出；
- `CcApiConnector`：登录成功、用户取消、已有连接恢复、session 失效、模型同步、默认模型选择和失败回滚；
- `ModelsSettingsPage`：CC API 卡片的未连接、连接中、已连接和失败状态；
- Provider 模型合并：新模型、missing 模型和用户启用状态保持；
- Logo 资源加载和桌面图标引用；
- `cccode://` scheme、窗口标题、应用标识、数据目录和 native channel 名称的基本检查；
- 运行 `dart analyze` 仅覆盖改动相关文件，配合对应 Flutter widget/unit tests。

验收标准：

1. 用户可在普通 CCCode 的“设置 → 模型”看到 CC API 卡片；
2. 点击后能在内置窗口完成 CC API 登录；
3. 登录成功后无需复制 Key，客户端能自动获得可用模型；
4. 新会话默认模型可以直接使用；
5. CC API 暂时不可用时不会破坏已有模型配置；
6. 应用界面和平台产物不再出现用户可见的 CCCode 名称；
7. `package:baocode/...` 保持可编译；
8. 相关测试和分析通过。

## 8. 实施顺序

1. 建立 CCCode 品牌资源和平台标识替换清单；
2. 加入 Logo 资源与应用图标变体；
3. 抽取或复用登录窗口、Sub2API adapter 的共享能力；
4. 实现 `CcApiConnector` 和安全状态存储；
5. 将 CC API 卡片接入模型设置页；
6. 增加中英文文案和相关测试；
7. 执行针对性分析、单测和 Widget 测试；
8. 最后做一次全局 CCCode 用户可见标识检查，不执行完整测试套件。
