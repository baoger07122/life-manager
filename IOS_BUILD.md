# Home OS iOS 云端构建流程

1. 在 GitHub 打开 `Actions → Build Home OS unsigned IPA → Run workflow`。
2. `render_url` 保持默认，或填写新的 Render HTTPS 地址。
3. 等 macOS runner 完成后，在该运行记录的 `Artifacts` 下载 `home-os-unsigned-ipa`。
4. 将 `HomeOS-unsigned.ipa` 上传到你的第三方自签服务，再按该服务的流程选择证书/描述文件完成签名。

这个工作流只生成未签名 IPA，不保存证书、私钥或描述文件。网站页面由 Render 地址提供，因此后续网页部署后，重新打开 App 即可读取新的线上版本；是否立即使用新页面仍由 App 内的版本检查和缓存策略决定。
