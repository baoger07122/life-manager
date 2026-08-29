# Home OS JSON 数据契约

兼容键：`home-os-v1`。原生备份文件顶层结构保持以下字段：

```text
foods[]
recipes[]
plans[]
prepChecks[]
petItems[]
pets[]
petEventCategories[]
petEvents[]
litterBoxState{}
litterOperations[]
petInventoryTransactions[]
petProductReviews[]
petPalatabilityReviews[]
activities[]
settings{}
```

日期继续使用 `yyyy-MM-dd` 字符串，标识符继续使用字符串。原生实现导入时允许缺少新增字段并使用默认值，导出时不得删除 Web 仍在使用的字段。

详细字段以 `ios-native/HomeOSNative/Models/HomeModels.swift` 为可执行契约。每次字段变更必须同步更新本文件、Swift 模型和 Web 类型定义。

## 宠物模块 V2 新增兼容字段

- `pets[]`：宠物档案；删除采用 `isDeleted` 软删除，历史事项保留名称快照。
- `petEventCategories[]`：用户自定义事项分类；删除后不再用于新事项。
- `petEvents[]`：事项时间轴，保存分类名和宠物名快照，并可关联猫砂操作。
- `litterBoxState`：单个猫砂盆的当前预测基准，不与家庭库存混用。
- `litterOperations[]`：初始化、补砂和换砂操作及各产品分配明细。
- `settings.petEventCollapsedDateGroups`：日期分组的展开/折叠记忆。
- `petItems[].unitConversionToBase`：非 kg/g 单位换算到 kg 的倍率。
- `petInventoryTransactions[]`：宠物物品入库、出库、调整和猫砂联动流水；当前库存由 `quantityChange` 求和。
- `petProductReviews[]`：用户对所有宠物物品的多次回购评价。
- `petPalatabilityReviews[]`：仅食品使用的分宠物适口性评价，保留宠物名称快照。
- `settings.managedBrands[]`：可用于宠物或食品模块的品牌库，包含适用范围与停用状态；旧备份缺少时由已有品牌和默认品牌生成。
- `petInventoryTransactions[].totalPrice` 与 `unitPrice`：新建物品的初始库存也作为入库流水记录可选购入总额和自动折算单价。

`petItems[].lowStockThreshold` 和 `foodRole` 仅为旧备份宽容读取字段；当前原生新建/编辑页面不再写入预警库存或食品用途。

旧备份缺少上述字段时使用空集合或 `nil`，不得因此拒绝导入。宠物用品历史字段缺失时使用安全默认值；导出时保留原有顶层集合和新增集合。
