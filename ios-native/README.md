# Home OS Native

完全原生 SwiftUI 重写工程，不包含 `WKWebView`。

- 测试 Bundle ID：`com.bao.homeos.native`，可与当前 Capacitor 版并存安装。
- 最新已发布原生版本：`10.28.3 (50)`；[打开 GitHub Pre-release](https://github.com/baoger07122/life-manager/releases/tag/ios-native-v10.28.3)，或[下载未签名 IPA](https://github.com/baoger07122/life-manager/releases/download/ios-native-v10.28.3/HomeOSNative-10.28.3-unsigned.ipa)。文件大小 `5,090,882` 字节，SHA-256 `fbf50fb27dfe266ce223a0ce6f584efc558091592dd357dfa29339ae439994aa`。
- 对应 Web 功能基线：`v8.25.1`。
- 本地数据文件：Application Support 下的 `home-os-v1.json`。
- 备份格式与 Web `home-os-v1` JSON 保持兼容。
- 入库正金额保留在原有 `totalPrice`/`unitPrice` 字段；出库成本按日期和创建顺序用移动加权平均重算，数据不足时保持空值并从可计算开销中排除。

GitHub Actions 使用 XcodeGen 生成 Xcode 工程并输出未签名 IPA。

开发、版本和组件准入规则见 `docs/native-rewrite/`。预览阶段不递增正式版本号；只有生成新 IPA 时才更新并发布版本。

当前原生版已进入宠物模块 V2：宠物物品两级分类、品牌库、库存流水、价格历史、用户回购评价、分宠物猫咪评价、猫砂盆预测、宠物事项时间轴、宠物档案、分类设置和首页联动。
