# Home OS Native

完全原生 SwiftUI 重写工程，不包含 `WKWebView`。

- 测试 Bundle ID：`com.bao.homeos.native`，可与当前 Capacitor 版并存安装。
- 当前原生版本：`0.1.25 (27)`；由 GitHub Actions 生成未签名 IPA。
- 对应 Web 功能基线：`v8.25.1`。
- 本地数据文件：Application Support 下的 `home-os-v1.json`。
- 备份格式与 Web `home-os-v1` JSON 保持兼容。

GitHub Actions 使用 XcodeGen 生成 Xcode 工程并输出未签名 IPA。

开发、版本和组件准入规则见 `docs/native-rewrite/`。预览阶段不递增正式版本号；只有生成新 IPA 时才更新并发布版本。

当前原生版已进入宠物模块 V2：宠物物品两级分类、品牌库、库存流水、价格历史、用户回购评价、分宠物猫咪评价、猫砂盆预测、宠物事项时间轴、宠物档案、分类设置和首页联动。
