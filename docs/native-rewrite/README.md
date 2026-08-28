# Home OS 原生 iOS 重写管理

本目录是 Home OS 原生版本的开发、设计和验收依据。Web 版继续独立运行，用于快速验证需求；确认后的功能再由原生 App 复现。

## 当前基线（2026-08-27）

- Web 功能基线：`v8.25.1`。
- 原生分支：`codex/ios-native-rewrite`。
- 原生 Bundle ID：`com.bao.homeos.native`，可与旧 Capacitor App 并存。
- 最近一次云端成功构建 IPA：`0.1.10 (11)`，GitHub Actions 运行 `33154889499`。
- 当前原生代码已使用 macOS 26 / 新版 Apple SDK 编译，系统 `TabView` 采用 iPhone 原生 Liquid Glass 外观。
- 已确认主导航：系统 `TabView`；首页 `house.fill`、食品 `takeoutbag.and.cup.and.straw.fill`、菜谱 `list.bullet.clipboard.fill`、宠物 `cat.fill`、设置 `gearshape.fill`。

“预览通过”不等于“已经发布 IPA”。只有 CI 构建成功并提供 IPA 后，版本才能登记为已发布。

## 固定开发路线

`Web 快速验证 → Swift Playgrounds 原生预览 → 用户确认 → 正式原生代码 → 编译/数据检查 → 必要时生成 IPA → 真机验收`

- Web 需求修改不自动代表原生功能已经完成。
- Playgrounds 只使用模拟数据，不证明持久化、备份、通知或前后台恢复正确。
- 预览修改不递增版本号、不生成 ZIP、不提交为正式发布。
- 只有需要生成新 IPA 时才确定并递增原生版本号。
- 不修改 Web `main`，不在原生正式 App 中嵌入 Web 页面。

## 文档入口

- `DEVELOPMENT_MANAGEMENT.md`：阶段、状态、版本、验收、变更和发布规则。
- `UI_COMPONENT_LIBRARY.md`：设计令牌、公共组件、状态及新增组件准入规则。
- `FUNCTION_BASELINE.md`：从 Web `v8.25.1` 冻结的功能范围和模块验收基线。
- `DATA_CONTRACT.md`：`home-os-v1` 备份结构与原生/Web 兼容约束。
- `PET_MODULE_V2_IMPLEMENTATION.md`：宠物模块 V2 的实现范围、限制和预览验收步骤。
- `PET_ITEMS_V1_IMPLEMENTATION.md`：宠物物品、库存流水、价格与双评价体系的实施基线。

## 代码入口

- `ios-native/HomeOSNative/Design/DesignSystem.swift`：统一设计令牌与公共 SwiftUI 组件。
- `ios-native/HomeOSNative/Views/UIComponentLibraryView.swift`：设置页内可操作的 UI 组件库。
- `ios-native/sync-playground.ps1`：把同一份预览原位同步到 Playgrounds 和 iCloud 临时文件夹。
