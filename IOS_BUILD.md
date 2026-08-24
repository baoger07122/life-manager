# Home OS iOS 云端构建流程

1. 在 GitHub 打开 `Actions → Build Home OS unsigned IPA → Run workflow`。
2. `render_url` 保持默认，或填写新的 Render HTTPS 地址。
3. 等 macOS runner 完成后，在该运行记录的 `Artifacts` 下载 `home-os-unsigned-ipa`。
4. 将 `HomeOS-unsigned.ipa` 上传到你的第三方自签服务，再按该服务的流程选择证书/描述文件完成签名。

这个工作流只生成未签名 IPA，不保存证书、私钥或描述文件。

iOS App 会先打开 IPA 内置的本地启动页，在后台预加载 Render 页面，加载成功后再进入 Home OS。网络较慢时会保留加载状态和“重新连接”按钮，不再直接显示白屏。

- 普通网页功能和 UI 更新：部署 Render 后即可通过 App 内“检查更新”加载，不需要重新安装 IPA。
- 本地启动页、Capacitor 插件、原生震动或通知能力变更：需要重新运行本工作流并安装新 IPA。
