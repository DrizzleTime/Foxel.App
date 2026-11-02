# Foxel

> **多账户隔离的私有云盘客户端** —— Android / iOS / Windows / macOS / Linux
> 当前版本 **v1.0.10**（`pubspec.yaml: 1.0.10+10`）

Foxel 是 Foxel 服务端的跨平台客户端，用于浏览、上传、下载、整理、播放自建服务器上的文件。
与常见云盘 App 不同，Foxel 把**账户当作一等公民**：每个账户是一套独立沙箱，拥有自己的登录态、下载目录、传输队列、浏览位置与媒体缓存。私人服务器、团队服务器、NAS 可以同时挂着，互不干扰。

---

## 目录

- [一、项目简介](#一项目简介)
- [二、主要功能](#二主要功能)
- [三、技术栈](#三技术栈)
- [四、安装与运行](#四安装与运行)
- [五、目录结构](#五目录结构)
- [六、使用示例](#六使用示例)
- [七、数据隔离模型](#七数据隔离模型)
- [八、已知限制](#八已知限制)
- [九、版本记录](#九版本记录)

---

## 一、项目简介

| 项目 | 说明 |
|---|---|
| 类型 | Flutter 客户端应用（`publish_to: none`，不发布到 pub.dev） |
| 包名 | `foxel`（Android applicationId `cc.foxel.app`） |
| 平台 | Android、iOS、Windows、macOS、Linux、Web（工程存在，非主要目标） |
| 依赖 | 需要一个运行中的 Foxel 服务端；公开测试站 `https://demo.foxel.cc`（用户名 / 密码均为 `admin`） |

**界面结构**：底部胶囊导航三个 tab —— `文件 / 任务 / 设置`。无账户时不显示底部导航，直接停在账户管理页的唯一空态；账户管理是设置页内的独立二级页，在其中点选账户即可切换。

---

## 二、主要功能

### 2.1 多账户与隔离

| 能力 | 说明 |
|---|---|
| 无限账户 | 手动添加或扫码添加；点选即切换，切换后自动回到「文件」页 |
| 四项隔离开关 | `独立下载目录` / `独立传输队列` / `记住浏览位置` / `独立媒体缓存`，默认全部开启，可在编辑账户页关闭 |
| 批量删除 | 账户管理页右上「编辑」进入多选，可勾选任意账户（含当前账户）批量删除；删空即回到空态 |
| 失效检测 | 启动时与切换前校验凭证，仅 401/403 判定为失效（网络异常不误判），列表标注「需重新验证」，本地沙箱数据保留 |
| 干净的删除语义 | 删除账户时同步清理其沙箱全部本地数据；旧版本会话只迁移一次并幂等清理残留 key，杜绝「删了又复活」 |

### 2.2 文件管理（`lib/features/drive`）

- **浏览**：目录导航与返回上级，顶部显示当前目录名与概要（子目录数 / 文件数 / 总大小）、当前目录搜索（前端过滤）
- **排序与视图**：按名称 / 大小 / 修改时间 / 类型排序，支持升倒序；网格视图与列表视图一键切换
- **单项操作**：下载、重命名、复制、移动、删除（单项下载不支持文件夹，需走多选批量下载）
- **上传**：选择本地文件上传到当前目录，带实时进度回调
- **新建文件夹**
- **多选批量**：长按条目或点「选择」进入多选模式，支持批量下载 / 移动 / 复制 / 删除 / 重命名
  - 批量下载：文件夹递归展开为文件队列，**保留相对目录结构**避免同名覆盖
  - 批量下载 / 移动 / 复制 / 删除走**受限并发（上限 3）**，逐项记录失败原因便于精确重试

### 2.3 批量重命名（`lib/features/drive/services/rename_rules.dart`）

五种规则，**先预览后执行**，冲突在预览阶段拦截，不提供强制覆盖：

| 规则 | 可配置项 |
|---|---|
| 查找替换 | 查找文本、替换文本、区分大小写、是否包含扩展名 |
| 前后缀 | 前缀、后缀 |
| 序号编号 | 起始值、步长、位数、插入位置（前 / 后）、分隔符 |
| 大小写转换 | 全小写 / 全大写 / 首字母大写 |
| 修改扩展名 | 新扩展名（仅文件，文件夹自动跳过） |

安全性处理：非法字符替换为 `_`、压缩空白、去首尾点、**按字素（characters）截断到 100 长度**、避开 Windows 保留设备名（`con`/`nul`/`com1`… 自动加 `foxel_` 前缀）、同目录重名与本批次内部重名检测。规则为纯 Dart 逻辑，不依赖 Flutter，单测覆盖（`test/rename_rules_test.dart`）。

### 2.4 传输任务（`lib/features/drive/controllers`）

- 任务列表实时展示上传 / 下载进度、已传输字节、失败原因
- 每个账户持有一个独立 `TransferTaskController`；「独立传输队列」关闭时任务可跨账户继续跑
- 切换账户 / 删除账户会中断在途任务，且中断状态不会被底层请求的迟到回调翻转
- 下载失败时清理本次新建的残缺文件（下载前已存在的文件不会被删除）

### 2.5 媒体预览（`lib/features/media`）

| 媒体 | 能力 |
|---|---|
| 图片 | 服务端缩略图（`/fs/thumb`，默认 320×320 cover）、查看器双击 / 双指缩放与复位 |
| 视频 | `media_kit` 播放 `/fs/stream`，支持倍速、进度拖拽（含缓冲区间）、音量、全屏、横竖屏切换、自动隐藏控制条 |
| 播放进度 | 按账户隔离持久化（`foxel_acc_<id>_vp_<hash>`），换设备/删账户互不污染 |

### 2.6 平台特性

- **Windows 便携版**：偏好数据写在 `<程序目录>/userdata/prefs.json`，删除程序目录即清空数据，不污染系统 AppData；写入走串行队列 + 临时文件 rename 的原子写，读取失败时禁止回写以避免覆盖
- **Windows 托盘常驻**：启动即显示主窗口并同时挂上托盘图标（设置页可改为「启动时最小化到托盘」）、关闭主界面只收进托盘、仅托盘菜单「退出」真正结束进程、左键双击显示主窗口、explorer 重启自动重挂图标、单实例（重复启动只唤起已有窗口）
- **Android**：默认下载目录 `/storage/emulated/0/Download/Foxel`
- **桌面端适配**：宽屏下内容宽度收敛居中（`ContentFrame`），与移动端版式一致

---

## 三、技术栈

| 领域 | 选型 | 用途 |
|---|---|---|
| 框架 | Flutter（Material 3），Dart SDK `^3.11.5` | 跨平台 UI（CI 固定 Flutter `3.47.5` stable） |
| 网络 | `http ^1.6.0` | 自研 `FoxelApi`（Bearer JWT + `{code,msg,data}` 响应解包） |
| 存储 | `shared_preferences ^2.5.3` | 账户索引与沙箱数据；Windows 上替换为自研 `PortablePrefsStore` |
| 媒体 | `media_kit`、`media_kit_video`、`media_kit_libs_video` | 视频播放与渲染 |
| 扫码 | `camera ^0.12.0`、`zxing2 ^0.2.4`、`image ^4.8.0` | 摄像头取帧 + QR 解码 |
| 文件 | `file_picker`、`open_filex`、`path_provider` | 选择本地文件、平台目录查询（`open_filex` 已引入，当前版本尚未在 UI 暴露「用系统程序打开」入口） |
| 质量 | `flutter_lints ^6.0.0`、`flutter_test` | 静态检查与单测 / 组件测试 |
| CI | GitHub Actions | `analyze.yml`（analyze + test）、`build.yml`（五平台构建 + tag 发布 Release） |

**服务端接口**（`FoxelApi` 实际调用，非客户端必须实现，仅供对接参考）：

| 端点 | 方法 | 用途 |
|---|---|---|
| `/api/auth/login` | POST | 表单登录，返回 `access_token` |
| `/api/auth/me` | GET | 拉取用户资料，兼作凭证校验 |
| `/api/fs/` 、`/api/fs/<path>` | GET | 目录列表（客户端固定 `page=1&page_size=200&sort_by=name&sort_order=asc`） |
| `/api/fs/recent` | GET | 最近文件（客户端内置 `page_size=6&sort_by=mtime&sort_order=desc`） |
| `/api/fs/file/<path>` | GET | 文件下载 / 读取字节 |
| `/api/fs/upload/<path>` | POST | Multipart 上传，带 `overwrite=true` |
| `/api/fs/stream/<path>` | GET | 视频流式播放 |
| `/api/fs/thumb/<path>` | GET | 缩略图，`w`/`h`/`fit` 参数 |
| `/api/fs/mkdir`、`/fs/rename`、`/fs/copy`、`/fs/move` | POST | 目录与文件写操作 |
| `/api/fs/<path>` | DELETE | 删除文件或目录 |
| `/api/adapters/usage` | GET | 存储适配器用量 |

地址规范化规则：输入不带 scheme 时自动补 `http://`，去掉结尾斜杠，非 `/api` 结尾时自动追加 `/api`。

---

## 四、安装与运行

### 4.1 环境要求

- Flutter SDK **≥ 3.11**（CI 使用 `3.47.5` stable）；Dart SDK `^3.11.5`
- 目标平台工具链：
  - Android：JDK 21 + Android SDK
  - Windows：Visual Studio（含 Desktop C++ 工作负载）
  - macOS / iOS：Xcode，且需自备 `Podfile`（仓库未提交）
  - Linux：GTK / Clang 等 Flutter Linux 依赖
- 一个可用的 Foxel 服务端（或用公开测试站 `https://demo.foxel.cc`）

### 4.2 从源码运行

```bash
git clone https://github.com/david88558855/Foxel.App.git
cd Foxel.App
flutter pub get          # 安装依赖
flutter run -d windows   # 运行到指定设备；-d chrome / -d <deviceId>
```

### 4.3 质量检查与构建

```bash
flutter analyze          # 静态检查（CI 为 --no-fatal-infos --no-fatal-warnings）
flutter test             # 单元与组件测试（重命名规则、账户管理页、冒烟）

flutter build apk --release --split-per-abi   # Android（等价脚本 scripts/build_android_split_apk.sh）
flutter build windows --release               # Windows
flutter build linux --release                 # Linux
flutter build macos --release                 # macOS
flutter build ios --release --no-codesign     # iOS（未签名）
```

`build.yml` 在推送 `v*` 标签时，把五平台产物汇总发布到 GitHub Release（发布说明模板在 `.github/release_notes.md`）。

### 4.4 直接下载安装包

当前 Release **v1.0.10**（点击表格中的格式即可下载）：

| 架构 | Windows | macOS | Linux | Android | iOS |
|---|---|---|---|---|---|
| x86-64 (64 位) | [ZIP](https://github.com/david88558855/Foxel.App/releases/latest/download/Foxel-windows-x86_64.zip) | — | [TAR.GZ](https://github.com/david88558855/Foxel.App/releases/latest/download/Foxel-linux-x86_64.tar.gz) | [APK](https://github.com/david88558855/Foxel.App/releases/latest/download/Foxel-android-x86_64.apk) | — |
| AArch64 / ARM64 | — | [ZIP](https://github.com/david88558855/Foxel.App/releases/latest/download/Foxel-macos-arm64.zip) | — | [APK](https://github.com/david88558855/Foxel.App/releases/latest/download/Foxel-android-arm64-v8a.apk) | [IPA](https://github.com/david88558855/Foxel.App/releases/latest/download/Foxel-ios-arm64-unsigned.ipa) |
| ARMv7 (32 位) | — | — | — | [APK](https://github.com/david88558855/Foxel.App/releases/latest/download/Foxel-android-armeabi-v7a.apk) | — |

> 历史版本见 [Releases](https://github.com/david88558855/Foxel.App/releases)。

**安装说明**

- **Windows**：解压 ZIP 后运行 `Foxel.exe`（便携版，数据在同目录 `userdata/`）。启动即显示主窗口，同时常驻系统托盘；关闭窗口只是收进托盘，需要从托盘菜单「退出」才会真正结束进程
- **macOS**：解压 ZIP 后拖入「应用程序」；首次打开可能需在「系统设置 › 隐私与安全性」中允许
- **Linux**：解压 TAR.GZ 后运行 `Foxel`
- **Android**：安装对应架构 APK，多数现代设备选 `arm64-v8a`
- **iOS**：IPA 为未签名版本，需通过 AltStore 等工具侧载

---

## 五、目录结构

```
Foxel.App/
├─ lib/
│  ├─ main.dart                 # 入口：初始化便携存储 + MediaKit，启动 FoxelDriveApp
│  ├─ app/
│  │  ├─ app.dart               # 全局 Material 3 主题（按钮 / 输入框 / AppBar / 对话框 / SnackBar）
│  │  └─ app_root.dart          # 应用根：账户索引、当前指针、切换、增删、失效重验
│  ├─ core/
│  │  ├─ api/
│  │  │  ├─ foxel_api.dart      # 服务端接口封装（REST 调用、响应解包、错误映射）
│  │  │  └─ foxel_api_exception.dart
│  │  ├─ models/                # Account、FileEntry、Session、IsolationPolicy…
│  │  ├─ storage/
│  │  │  ├─ account_store.dart          # 账户索引与沙箱读写（串行队列 + 一次性迁移）
│  │  │  ├─ download_dir_store.dart     # 账户级下载目录、可写探测、Android 权限引导
│  │  │  ├─ browse_state_store.dart     # 浏览位置 / 排序 / 视图模式
│  │  │  ├─ desktop_window_store.dart    # 「启动时最小化到托盘」开关（与 runner 共用标记文件）
│  │  │  └─ portable_prefs_store.dart   # Windows 便携版 JSON 存储（原子写 + 写队列）
│  │  ├─ theme/design_tokens.dart       # 设计令牌唯一来源（颜色 / 圆角 / 间距 / 字号）
│  │  ├─ widgets/content_frame.dart     # 桌面端宽度收敛容器
│  │  ├─ utils/path_utils.dart
│  │  └─ app_version.dart
│  └─ features/
│     ├─ accounts/              # 账户管理页、账户表单（别名 / 服务器 / 四项隔离开关）、头像组件
│     ├─ auth/                  # 扫码登录页（camera + zxing2）、QR 载荷解析
│     ├─ drive/
│     │  ├─ pages/              # drive_shell_page（底部导航壳）、file_browser_page、
│     │  │                      # transfer_tasks_page、batch_rename_page、directory_picker_page
│     │  ├─ controllers/transfer_task_controller.dart   # 上传/下载任务队列与中断语义
│     │  └─ services/rename_rules.dart                  # 批量重命名规则与冲突检测（纯逻辑）
│     ├─ media/                 # video_player_page、image_viewer_page、播放进度存储
│     └─ settings/              # 设置页：下载目录、存储用量、启动形态开关、清除本地数据、账户管理入口
├─ test/                        # rename_rules_test / account_center_test / widget_test
├─ android/ ios/ macos/ linux/ windows/ web/   # 各平台工程（windows/runner 含托盘实现 tray_icon.*）
├─ scripts/build_android_split_apk.sh          # Android 分架构 APK 构建脚本
└─ .github/
   ├─ workflows/analyze.yml     # analyze + test
   ├─ workflows/build.yml       # 五平台构建 + tag 发布 Release
   └─ release_notes.md          # Release 说明模板（占位符 __REPO__ / __TAG__）
```

---

## 六、使用示例

### 6.1 首次启动：添加账户

1. 安装完成后启动，无账户时直接停在**账户管理页空态**
2. 点「添加账户」→ 选择「手动输入」
3. 填写字段后点「验证并添加」：

| 字段 | 示例 | 说明 |
|---|---|---|
| 显示名称 | `家里 NAS` | 选填；留空回退到用户名，用于列表展示与下载目录命名 |
| 服务器地址 | `https://demo.foxel.cc` | 不带 scheme 时自动补 `http://` |
| 用户名 | `admin` | |
| 密码 | `admin` | |

4. 验证成功后自动登录并切换到该账户；同时在「设置 › 下载目录」落定该账户的默认目录

### 6.2 扫码添加账户

网页端生成内容为下列 JSON 的二维码：

```json
{ "base_url": "https://demo.foxel.cc", "token": "<服务端签发的 access_token>" }
```

App 内：**添加账户 → 扫码添加**，用后置 / 外接摄像头对准二维码，解码后自动创建账户并切换。
缺少 `base_url` 或 `token`、内容非合法 JSON 时会给出明确错误提示。

### 6.3 切换账户

**设置 → 账户管理 → 点选目标账户**（列表中带「使用中」胶囊的是当前账户）。
切换成功后提示「已切换到『X』，数据与其他账户隔离」并自动回到「文件」页；凭证失效则回滚并提示重新验证。

### 6.4 下载到账户专属目录

默认下载目录规则：

| 平台 | 默认目录 |
|---|---|
| Android | `/storage/emulated/0/Download/Foxel` |
| 其他平台 | `<系统下载目录>/Foxel/<显示名称 或 账户ID>` |

在 **设置 → 下载目录** 中可手动输入路径、点「浏览...」选择系统目录、或「恢复默认」。保存前会做可写探测；Android 10+ 写公共目录时若未获「所有文件访问」权限，会引导前往系统设置授权。

Windows 另有 **设置 → 启动时最小化到托盘** 开关：关闭（默认）时启动即显示主窗口并常驻托盘，开启后启动只留托盘图标、主窗口由托盘菜单唤起。开关状态记在 `<程序目录>/userdata/.start-minimized`（文件存在即开启），改动只影响下一次启动。

### 6.5 批量重命名一组照片

1. 在文件页点右上角「选择」（或长按任一照片）进入多选
2. 勾选 `IMG_0431.jpg` … `IMG_0470.jpg`
3. 底部「更多」→「批量重命名」
4. 规则选「查找替换」：查找 `IMG_` → 替换为 `旅行_`
5. 预览列表确认新旧名后点「应用」

预览阶段会标出「名称未变化」「目标名已存在」「与第 N 项重名」，有冲突的条目不会被执行。

### 6.6 直接播放视频 / 预览图片

文件页点开 `.mp4` / `.mkv` 等视频进入播放页（自动携带 JWT 请求流式地址），点开图片进入缩放查看器；播放进度下次进入自动续播，且进度与其他账户隔离。

---

## 七、数据隔离模型

**全局层（唯一）**

| Key | 内容 |
|---|---|
| `foxel_accounts_index` | 账户索引（不含 token） |
| `foxel_active_account_id` | 当前账户指针 |
| `foxel_migration_v2_done` | 旧版本会话迁移只执行一次的标记 |

**账户沙箱（`foxel_acc_<id>_*`）**

| 维度 | 存储 Key | 用户可见效果 |
|---|---|---|
| 登录凭证 | `foxel_acc_<id>_token` | 切换账户不会串登录态 |
| 下载目录 | `foxel_acc_<id>_download_dir` | 不同账户的文件分开存放 |
| 传输队列 | 内存中按账户持有控制器 | 任务页只显示当前账户的任务 |
| 浏览位置 | `foxel_acc_<id>_browse_state` | 切回后恢复上次目录 / 排序 / 视图 |
| 媒体缓存 | `foxel_acc_<id>_vp_<hash>` | 播放进度按账户隔离 |

四项隔离开关关闭后，该账户与其他同样关闭该开关的账户共用对应资源。

**各平台数据位置**

| 平台 | 位置 |
|---|---|
| Windows | `<程序目录>/userdata/prefs.json`（便携，删目录即清空） |
| macOS / Linux | 系统应用支持目录 |
| Android / iOS | 应用私有目录（卸载即清除） |

---

## 八、已知限制

- **目录列表不分页**：固定拉取单页 200 条（`page_size=200`），超大目录暂不加载后续页
- **批量操作并发上限 3**：服务端无打包下载接口，文件夹下载按递归展开为文件队列，超大目录耗时较长
- **上传为单选**：一次只能上传一个文件（`pickFiles` 未开启多选）
- **扫码入口复用登录页**，尚未做成独立页面
- **「清除本地数据」不删除已下载到磁盘的文件**（避免误删用户资料）
- **Windows**：关闭主窗口后进程仍在系统托盘运行，需从托盘菜单「退出」才真正结束；托盘图标可能被系统收纳进通知区域溢出区
- **Android 10+**：写入公共目录需要「所有文件访问」权限，未授权时该目录不可写
- **iOS / macOS**：仓库未提交 `Podfile`，首次构建需在本工程执行 `flutter build ios/macos` 由 Flutter 生成或手工 `pod install`
- 网络图片缓存尚未按账户分区；账户级密码 / 生物识别锁未实现

---

## 九、版本记录

| 版本 | 时间 | 说明 |
|---|---|---|
| **v1.0.10** | 2026-10-28 | 桌面端字体改为 Arial + 中文近似黑体（微软雅黑 / 苹方 / Noto），修掉 Windows 上汉字回落到宋体、小字号发虚的问题；移动端保持系统字体 |
| **v1.0.9** | 2026-10-28 | 修 bug 一批：取消批量操作后批量栏卡死（P0）、无法移动到当前目录的子文件夹、下载中断毁掉本地同名文件、独立下载目录开关对老账户无效、批量重命名后列表不刷新、暂停态快进自动播放，外加 12 处边界问题 |
| **v1.0.8** | 2026-10-28 | 提示条改版：文件页的 SnackBar 从底部黑色浮条改为顶部搜索框位置的浅蓝提示条（不压导航、不挤列表），失败提示走红色系 |
| **v1.0.7** | 2026-10-22 | 全新应用图标：主色渐变 + 白狐狸（沿用服务端 logo 矢量），五平台统一，Windows 圆角、Android 自适应图标 |
| **v1.0.6** | 2026-10-17 | Windows 系统托盘常驻：启动托盘化、关闭只收起、仅托盘可退出、单实例；修复便携版多实例互相写坏 `prefs.json` |
| **v1.0.5** | 2026-10-17 | 文件批量操作与批量重命名；修复删除 / 切换账户竞态、便携版写盘空窗等阻断级问题 |
| v1.0.3 | 2026-10-17 | 文件批量操作与批量重命名；macOS 沙箱网络权限修复 |
| v1.0.2 | 2026-10-16 | 账户体系定稿；多选批量删除；下载目录默认名优先使用显示名称 |
| v1.0.0 | 2026-09-16 | 首个公开版本：多账户创建 / 切换、文件浏览与传输 |

> 更详细的发版说明见各版本的 GitHub Release 正文。

---

**测试服务端**：`https://demo.foxel.cc`（用户名 / 密码均为 `admin`）
