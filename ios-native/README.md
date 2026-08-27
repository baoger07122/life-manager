# Home OS Native

完全原生 SwiftUI 重写工程，不包含 `WKWebView`。

- 测试 Bundle ID：`com.bao.homeos.native`，可与当前 Capacitor 版并存安装。
- 原生版本：`0.1.5 (6)`。
- 对应 Web 功能基线：`v8.25.1`。
- 本地数据文件：Application Support 下的 `home-os-v1.json`。
- 备份格式与 Web `home-os-v1` JSON 保持兼容。

GitHub Actions 使用 XcodeGen 生成 Xcode 工程并输出未签名 IPA。
