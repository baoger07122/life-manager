# Home OS JSON 数据契约

兼容键：`home-os-v1`。原生备份文件顶层结构保持以下字段：

```text
foods[]
recipes[]
plans[]
prepChecks[]
petItems[]
activities[]
settings{}
```

日期继续使用 `yyyy-MM-dd` 字符串，标识符继续使用字符串。原生实现导入时允许缺少新增字段并使用默认值，导出时不得删除 Web 仍在使用的字段。

详细字段以 `ios-native/HomeOSNative/Models/HomeModels.swift` 为可执行契约。每次字段变更必须同步更新本文件、Swift 模型和 Web 类型定义。
