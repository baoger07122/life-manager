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
petInventoryBalanceAllocations[]
petProductReviews[]
petPalatabilityReviews[]
activities[]
settings{}
```

日期继续使用 `yyyy-MM-dd` 字符串，标识符继续使用字符串。原生实现导入时允许缺少新增字段并使用默认值，导出时不得删除 Web 仍在使用的字段。
界面层统一转换为 `yyyy年M月d日` 中文日期；显示格式变化不修改备份值。

详细字段以 `ios-native/HomeOSNative/Models/HomeModels.swift` 为可执行契约。每次字段变更必须同步更新本文件、Swift 模型和 Web 类型定义。

## 宠物模块 V2 新增兼容字段

- `pets[]`：宠物档案；删除采用 `isDeleted` 软删除，历史事项保留名称快照。
- `petEventCategories[]`：用户自定义事项分类；删除后不再用于新事项。
- `petEvents[]`：事项时间轴，保存分类名和宠物名快照，并可关联猫砂操作。
- `petEvents[].name`：保存具体事项；用户未填写时写入 `categoryNameSnapshot` 作为显示标题，以兼容字段非空约束并避免录入重复。
- `litterBoxState`：单个猫砂盆的当前预测基准，不与家庭库存混用。
- `litterOperations[]`：初始化、补砂和换砂操作及各产品分配明细。
- `settings.petEventCollapsedDateGroups`：日期分组的展开/折叠记忆。
- `petItems[].unitConversionToBase`：非 kg/g 单位换算到 kg 的倍率。
- `petItems[].packageType`：可选包装形式，当前预设仅为袋或罐；与 `spec` 单件规格及 `unit` 库存单位分别保存。
- `petItems[].variant`：宠物食品保存口味，宠物用品保存型号或款式；不得再写入 `spec` 的副本。品牌、名称、口味、包装形式和规格完全相同时视为疑似重复产品。
- `petInventoryTransactions[]`：宠物物品入库、出库、调整和猫砂联动流水；当前库存由 `quantityChange` 求和。
- `petInventoryTransactions[].expirationDate`：入库流水的批次到期日；只作用于该笔入库，不代表产品的全部库存。
- `petInventoryTransactions[].tracksExpirationBatch`：可选批次迁移标记。旧流水首次迁移时，只有之后没有未分配出库或向下修正的入库才作为可确认批次；不确定的旧余额保留在“未设日期”组。
- `petInventoryTransactions[].batchAllocations[]`：可选出库分配，按 `sourceBatchID` 关联原入库流水，并记录从该入库批次扣减的数量。多条入库即使到期日相同仍保留独立来源；同一日期的消费按入库先后扣减。
- `petInventoryBalanceAllocations[]`：可选的现存余额日期重分类记录；包含商品、来源批次、生效前的来源余量下限、目标日期、数量、生效日期和创建时间。未设日期库存使用稳定的合成来源标识；已确认批次或先前重分类批次也可作为来源。它只重新归类生效时仍剩余的数量，不新增或修改入库流水、活动数量、库存成本或加权均价。后续出库可引用重分类记录 ID；删除该出库后，按原批次日期重放并恢复余额。历史修改若使来源余量低于该次调整前记录的下限，整次操作失败，以避免把新日期套到无关历史库存上。
- 批次余额由已追踪入库数量减去明确分配到该批次的出库数量得到；未设日期余额为当前流水总库存减去可确认批次余额。旧出库没有可靠批次来源时不补造日期归属，历史数量和金额仍由原流水保留。
- `petProductReviews[]`：用户对所有宠物物品的多次回购评价。
- `petProductReviews[].dimensionScores`：本次评价各维度的 1～5 整数分数字典；综合分不重复存储，由维度算术平均得到。旧记录缺少时使用原 `repurchaseLevel` 作为兼容评分。
- 编辑物品评价时按 `petProductReviews[].id` 更新原记录，保留 `createdAt`，只更新日期、评分、文字与 `updatedAt`。
- `petPalatabilityReviews[]`：仅食品使用的分宠物适口性评价，保留宠物名称快照。
- `settings.managedBrands[]`：可用于宠物或食品模块的品牌库，包含适用范围与停用状态；旧备份缺少时由已有品牌和默认品牌生成。
- `petInventoryTransactions[].totalPrice` 与 `unitPrice`：入库保存原始购入总额和折算单价；出库保存当时库存的移动加权平均成本快照。只使用正数入库金额计入成本池；遇到无价库存时不按零元估算，无法可靠计算的出库保持空值。修改或删除入库金额、修改流水数量或日期后，原位重放该物品历史并更新受影响的出库快照。新建物品的初始库存也使用同一入库结构。
- 删除一条库存流水时，会在副本中同时移除对应活动记录并重放该物品剩余历史；若后续出库或修正因此变成无效历史，整次删除失败并保留原数据。删除迁移自旧版购买记录的入库时，也同步移除其对应旧版记录，避免下次启动重新迁移。猫砂联动流水必须通过成组猫砂操作管理，不允许单条删除。

`petItems[].lowStockThreshold` 和 `foodRole` 仅为旧备份宽容读取字段；当前原生新建/编辑页面不再写入预警库存或食品用途。

`petEvents[].petIDs` 与 `petNameSnapshots` 继续保留以兼容旧备份；当前原生新建或编辑宠物事项统一写入空数组，不再按宠物筛选事项。

旧备份缺少上述字段（包括 `petInventoryBalanceAllocations[]`）时使用空集合或 `nil`，不得因此拒绝导入。宠物用品历史字段缺失时使用安全默认值；导出时保留原有顶层集合和新增集合。
