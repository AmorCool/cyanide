# Cyanide 1.2.24 源码整合说明（App Downgrade）

本文件说明如何将 **IPA 逆向得到的 App Downgrade 功能** 整合进 **原版源码工程**，
以及如何在 GitHub Actions 上构建验证。

---

## 1. 背景

- **IPA**：`Cyanide-1.2.24.ipa`（`com.zeroxjf.ios-cyanide1`，arm64）
- **原版源码**：`cyanide-1.2.24.zip`（GitHub 仓库 `zeroxjf/cyanide`）
- **差异**：IPA 中包含 `AppListViewController`（应用列表 + App Downgrade）等新类，
  而原版源码中没有。本次整合把从二进制逆向重建的 `AppListViewController`
  （含完整 App Downgrade 流程）补回源码工程。

## 2. 逆向结论摘要

App Downgrade 并非"直接安装旧 IPA"，而是复用 **App Store 旧版本分发通道**：

1. **TrackID 解析**：用 iTunes Lookup API
   `https://itunes.apple.com/lookup?bundleId=%@&limit=1&media=software&country=%@`
   把 bundleID 解析为 trackID，失败时按 17 个 App Store 国家/地区代码逐个回退。
2. **版本枚举**：用第三方镜像服务
   `https://apis.bilin.eu.org/history/<trackID>`
   获取该应用的全部历史版本（含 `AppVersion`、`versionId`）。
3. **用户选择版本**：弹出版本列表（或手动输入 Version ID）。
4. **注入执行**：通过 `RemoteCallSession` 附加到 SpringBoard，
   `dlopen(/System/Library/PrivateFrameworks/StoreKitUI.framework/StoreKitUI)`，
   构造 `SKUIItemOffer` / `SKUIItem` / `SKUIClientContext` /
   `SKUIItemStateCenter`，调用
   `_performPurchases:hasBundlePurchase:withClientContext:completionBlock:`
   向 `itunesstored`（`com.apple.itunesstore`）提交指向旧版本 ID 的购买/下载请求。

> 关键点：`SKUIItemStateCenter` 的 `_performPurchases:` 选择器串、StoreKitUI 框架路径、
> itunesstored 服务名、版本历史服务 URL 全部从二进制字符串表直接还原。

## 3. 本次整合的文件

| 文件 | 类型 | 说明 |
|------|------|------|
| `Cyanide/installer/AppListViewController.h` | 新增 | AppInfo 值对象 + 应用列表控制器接口 |
| `Cyanide/installer/AppListViewController.m` | 新增 | 应用枚举 / 搜索 / Downgrade 全流程 / StoreKitUI 注入 / Block Updates 入口 |
| `Cyanide/installer/BlockUpdatesViewController.h` | 新增 | Block Updates（阻止应用更新）控制器接口 |
| `Cyanide/installer/BlockUpdatesViewController.m` | 新增 | 应用枚举 / 阻止列表持久化 / commit |
| `Cyanide/SettingsViewController.m` | 修改 | Quick Actions 增加「App Downgrade」（row 4）与「Block Updates」（row 5）入口 |
| `.github/workflows/build.yml` | 新增 | GitHub Actions 构建工作流 |
| `INTEGRATION_NOTES.md` | 新增 | 本说明文件 |

### 3.3 入口位置（重要）

两个功能入口均位于 **Settings → 顶部「Quick Actions」栏**：

| 行 | 功能 | 目标控制器 |
|----|------|-----------|
| 0 | Clean Up | — |
| 1 | Respring | — |
| 2 | Reset All Packages | — |
| 3 | Check for Updates | — |
| **4** | **App Downgrade** | `AppListViewController` |
| **5** | **Block Updates** | `BlockUpdatesViewController` |

> 不在 Tweak 栏 / System 栏。若编译后未看到，请先展开 Settings 根页的 Quick Actions 区。
> AppListViewController 内的每个应用 action sheet 也有「Block Updates」入口（会预选该应用）。

### 3.4 Block Updates 机制说明

- `loadApps` 用 `LSApplicationWorkspace` 枚举已安装应用（IPA 原版用 `mobile_installation_proxy`，功能等价）。
- 用户勾选要阻止更新的应用（`waitingApps` NSSet），点右上角 **Commit** 提交。
- 提交逻辑：把 blocked bundle id 列表写入 `com.apple.MobileStore.plist`（键 `CyanideBlockedUpdates`）+ `notify_post` 通知 cfprefsd，并记录
  `[OK] Blocked updates for: %s` / `[OK] Unblocked updates for: %s`（与 IPA 日志一致）。
- 阻止更新最终生效需要 respring/reboot（App Store 自动更新在后台进程读取该配置）。

### 3.1 为什么不需要改 Xcode 工程文件？

该工程使用 Xcode 26.2 的 `PBXFileSystemSynchronizedRootGroup`：
`Cyanide/` 目录下的新文件会被 **自动同步进 target**，无需修改 `project.pbxproj`。

### 3.2 新增文件对源码基础设施的复用

- `RemoteCallSession`（`TaskRop/RemoteCall.h`）— SpringBoard 注入通道
- `r_session_*` 系列（`tweaks/remote_objc.h`）— 远程 ObjC 调用 / 远程 dlopen / 远程内存
- `log_user`（`LogTextView.h`）— 统一日志
- 入口放在 `SettingsViewController` 的 Quick Actions（`RootSectionActions`，5 行）

## 4. 构建方法

### 4.1 本地（macOS + Xcode）

```bash
# 1. 构建 XPF 内核原语库（生成 Cyanide/XPF/output/ios/libxpf.dylib）
make -C Cyanide/XPF output/ios/libxpf.dylib

# 2. 用 build.sh 构建并打包 IPA
./scripts/build.sh SCHEME=Cyanide CONFIG=Debug SDK=iphoneos
# 产物：build/Cyanide-<版本>.ipa
```

### 4.2 GitHub Actions

仓库根目录已包含 `.github/workflows/build.yml`。推送到 GitHub 后：

1. 打开仓库 → **Actions** 标签 → `Build Cyanide IPA` 工作流
2. 点击 **Run workflow**（或推送代码自动触发）
3. 构建完成 → 在 **Summary / Artifacts** 下载 `Cyanide-ipa` 压缩包
4. 解压得到 `.ipa`，用 AltStore / TrollStore / Sideloadly 侧载

> 注意：工作流使用 `macos-14` runner（含 Xcode 15.4）。
> 若你的环境需要其他 Xcode 版本，修改 `build.yml` 中的 `xcode-select` 行。

## 5. 依赖与前置条件

| 依赖 | 用途 | 何时需要 |
|------|------|----------|
| Xcode（≥ 15） | 编译 iOS App、链接 XPF | 构建 |
| `make`、`clang` | 编译 `libxpf.dylib`（Makefile） | 构建 |
| `ldid` | 对 `libxpf.dylib` 签名 | 构建（iOS 目标） |
| `xcbeautify`（可选） | 美化 xcodebuild 输出 | 构建 |
| 网络 | 拉取 XPF 子模块依赖 | 构建 |

**Git 子模块**：工程引用 `Cyanide/XPF` 内含 `external/ChOma`（已随源码包提供）。
若从 Git 克隆，请使用 `git clone --recursive` 或 `git submodule update --init --recursive`。

## 6. 已知限制与风险

1. **StoreKitUI 注入为运行时动态调用**：`SKUIItemOffer` / `SKUIItem` 的初始化走
   `initWithItemDictionary:` / `init` + KVC 兜底，具体属性可能随 iOS 版本变化。
   若目标 iOS 版本属性名不同，需按版本调整 `setValue:forKey:` 的键名。
2. **App 枚举依赖私有 API** `LSApplicationWorkspace`（运行时 `NSClassFromString`）。
   原版二进制使用 `mobile_installation_proxy` 枚举；两种方式在越狱环境均可用。
3. **版本历史服务为第三方**：`apis.bilin.eu.org` 若不可达，"Failed to get versions"。
4. **越狱依赖**：App Downgrade 的注入路径需要内核原语（`libxpf.dylib`）与
   SpringBoard 通道，仅在越狱设备上可用。构建本身不依赖越狱。

## 7. 可扩展方向

- IPA 中另有 `BlockUpdatesViewController`（阻止 App 更新）尚未整合，可参考
  `AppListViewController` 的模式补回。
- IPA 还含 App Store 登录 / IPA 解密器（`IPADecryptor`）相关代码，属独立功能。

---

*整合基于对 Cyanide-1.2.24.ipa 的静态逆向（符号表 + 字符串建模 + ARM64 反汇编），
重建代码复用了原版源码的 RemoteCall 基础设施。*
