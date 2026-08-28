import SwiftUI

struct UIComponentLibraryView: View {
    @State private var sampleText = ""
    @State private var selectedChip = "全部"
    @State private var status: HomeStatusKind = .empty
    @State private var quickManagementEnabled = true
    @State private var showToast = false
    @State private var showDeleteAlert = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HomeMetrics.sectionSpacing) {
                PageTitle(title: "UI 组件库", subtitle: "统一令牌与组件预览 · 不连接正式数据")
                typographySection
                colorSection
                metricsSection
                containerSection
                listAndShortcutSection
                actionSection
                formSection
                feedbackSection
                stateSection
                libraryStatusSection
            }
            .padding(.horizontal, HomeMetrics.pageInset)
            .padding(.vertical, 18)
        }
        .background(HomeTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if showToast {
                HomeToastView(message: "示例操作已完成")
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("删除这条示例内容？", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { NativeHaptics.warning() }
        } message: {
            Text("这里只展示系统删除确认，不会修改正式数据。")
        }
    }

    private var typographySection: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "字体层级")
                Text("以下是实际渲染尺寸，不是说明文字。")
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
                typeScaleRow("页面标题", sample: "我的物品", font: HomeTypography.pageTitle, note: "22pt / Semibold", color: HomeTheme.blue)
                typeScaleRow("分区标题", sample: "食品快捷管理", font: HomeTypography.sectionTitle, note: "17pt / Semibold", color: HomeTheme.orange)
                typeScaleRow("卡片标题", sample: "低温牛奶", font: HomeTypography.cardTitle, note: "15pt / Semibold", color: HomeTheme.success)
                typeScaleRow("正文", sample: "冷藏保存，开封后尽快饮用", font: HomeTypography.body, note: "15pt / Regular", color: HomeTheme.muted)
                typeScaleRow("辅助文字", sample: "更新于今天 10:30", font: HomeTypography.supporting, note: "12pt / Regular", color: HomeTheme.muted)
            }
        }
    }

    private var colorSection: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "语义颜色")
                HStack(spacing: 10) {
                    colorToken("主色", HomeTheme.blue)
                    colorToken("成功", HomeTheme.success)
                    colorToken("提醒", HomeTheme.orange)
                    colorToken("危险", HomeTheme.danger)
                }
            }
        }
    }

    private var metricsSection: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "尺寸与圆角")
                HStack(spacing: 10) {
                    metricExample("卡片", value: "22", radius: HomeMetrics.cardRadius)
                    metricExample("控件", value: "14", radius: HomeMetrics.controlRadius)
                    metricExample("点击区", value: "44", radius: 12)
                }
                Text("页面边距 18pt · 分区间距 16pt · 控件高度 44pt")
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
            }
        }
    }

    private var containerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: "容器与数据")
            HStack(spacing: 10) {
                HomeStatCard(title: "全部物品", value: "256")
                HomeStatCard(title: "即将到期", value: "3", color: HomeTheme.orange)
            }
            HomeCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("标准卡片标题").font(HomeTypography.cardTitle)
                    Text("业务页面使用统一内边距、圆角和文字层级，不单独复制样式。")
                        .font(HomeTypography.body)
                        .foregroundStyle(HomeTheme.muted)
                }
            }
        }
    }

    private var listAndShortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: "列表与快捷入口")
            HomeCard {
                VStack(spacing: 0) {
                    HomeListRow(title: "低温牛奶", subtitle: "冰箱 · 8 月 31 日到期", icon: "takeoutbag.and.cup.and.straw.fill", trailing: "1")
                    Divider()
                    HomeListRow(title: "番茄炒蛋", subtitle: "家常菜 · 已收藏", icon: "list.bullet.clipboard.fill", trailing: "4 步")
                }
            }
            HomeCard {
                HStack(spacing: 8) {
                    HomeQuickAction(title: "新增食品", icon: "plus.circle.fill") { showExampleToast() }
                    HomeQuickAction(title: "临期提醒", icon: "exclamationmark.triangle.fill", color: HomeTheme.orange) { showExampleToast() }
                    HomeQuickAction(title: "宠物状态", icon: "cat.fill", color: HomeTheme.success) { showExampleToast() }
                    HomeQuickAction(title: "数据备份", icon: "externaldrive.fill", color: HomeTheme.muted) { showExampleToast() }
                }
            }
        }
    }

    private var actionSection: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "按钮与标签")
                Button("主要操作") { NativeHaptics.tap() }
                    .buttonStyle(HomePrimaryButtonStyle())
                HStack(spacing: 10) {
                    Button("次要操作") { NativeHaptics.tap() }
                        .buttonStyle(HomeSecondaryButtonStyle())
                    Button("危险操作") { NativeHaptics.warning() }
                        .buttonStyle(HomeDangerButtonStyle())
                }
                HStack(spacing: 8) {
                    ForEach(["全部", "食品", "宠物"], id: \.self) { item in
                        Button {
                            selectedChip = item
                            NativeHaptics.selection()
                        } label: {
                            HomeChip(title: item, selected: selectedChip == item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 12) {
                    HomeIconButton(icon: "chevron.left", accessibilityLabel: "返回") { NativeHaptics.tap() }
                    HomeIconButton(icon: "ellipsis", accessibilityLabel: "更多") { NativeHaptics.tap() }
                    HomeIconButton(icon: "square.and.arrow.up", accessibilityLabel: "分享", color: HomeTheme.blue) { NativeHaptics.tap() }
                    Spacer()
                    HomeFloatingAddButton { showExampleToast() }
                }
                Text("依次展示图标按钮、返回/更多/分享入口和浮动新增按钮。")
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
            }
        }
    }

    private var formSection: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "表单")
                HomeFieldLabel(title: "名称", required: true)
                TextField("请输入名称", text: $sampleText)
                    .textFieldStyle(HomeTextFieldStyle())
                HomePropertyRow(title: "分类", value: "食品", icon: "tag.fill") {
                    NativeHaptics.selection()
                }
                HomePropertyRow(title: "到期日期", value: "2026-08-31", icon: "calendar") {
                    NativeHaptics.selection()
                }
                HomeToggleRow(title: "加入首页快捷管理", subtitle: "可在首页快速调整库存", isOn: $quickManagementEnabled)
                Text("输入框与属性选择行属于候选组件，确认后才能用于业务页面。")
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
            }
        }
    }

    private var feedbackSection: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "反馈与弹窗")
                HStack(spacing: 10) {
                    Button("显示 Toast") { showExampleToast() }
                        .buttonStyle(HomeSecondaryButtonStyle())
                    Button("删除确认") {
                        NativeHaptics.warning()
                        showDeleteAlert = true
                    }
                    .buttonStyle(HomeDangerButtonStyle())
                }
                Text("Toast、删除确认、新增/编辑弹窗、日期选择器需要分别确认动画和按钮顺序。")
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
            }
        }
    }

    private var stateSection: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "页面状态")
                Picker("状态", selection: $status) {
                    Text("空").tag(HomeStatusKind.empty)
                    Text("加载").tag(HomeStatusKind.loading)
                    Text("错误").tag(HomeStatusKind.error)
                    Text("成功").tag(HomeStatusKind.success)
                }
                .pickerStyle(.segmented)
                HomeStatusView(kind: status, title: statusTitle, message: statusMessage)
            }
        }
    }

    private var libraryStatusSection: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 10) {
                HomeSectionHeader(title: "组件库范围")
                statusRow("已确认", detail: "主导航、页面底色、标准卡片、当前页面标题基线", color: HomeTheme.success)
                statusRow("本轮调整", detail: "22pt 页面标题、15pt 输入正文、字号演示", color: HomeTheme.blue)
                statusRow("候选", detail: "按钮、表单、列表、快捷入口、Toast、删除确认和页面状态", color: HomeTheme.orange)
                Text("后续还需建立：新增/编辑弹窗、图片选择、日期与保质期、搜索筛选、排序、快捷数量、通知权限、文件导入和错误恢复。")
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
            }
        }
    }

    private var statusTitle: String {
        switch status {
        case .empty: "暂无内容"
        case .loading: "正在加载"
        case .error: "加载失败"
        case .success: "保存成功"
        }
    }

    private var statusMessage: String {
        switch status {
        case .empty: "新增第一条内容后会显示在这里"
        case .loading: "正在读取本地数据"
        case .error: "数据没有被修改，可以重新尝试"
        case .success: "内容已经保存在本机"
        }
    }

    private func typeScaleRow(_ title: String, sample: String, font: Font, note: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(HomeTypography.supporting.weight(.semibold)).foregroundStyle(HomeTheme.muted)
                Spacer()
                Text(note).font(.system(size: 10, design: .monospaced)).foregroundStyle(HomeTheme.muted)
            }
            Text(sample)
                .font(font)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func colorToken(_ title: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Circle().fill(color).frame(width: 28, height: 28)
            Text(title).font(HomeTypography.supporting)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricExample(_ title: String, value: String, radius: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text(value).font(HomeTypography.cardTitle)
            Text(title).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(HomeTheme.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func statusRow(_ title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(HomeTypography.cardTitle)
                Text(detail).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
            }
        }
    }

    private func showExampleToast() {
        NativeHaptics.success()
        withAnimation(.spring(duration: 0.28, bounce: 0.10)) { showToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1300))
            withAnimation(.easeOut(duration: 0.18)) { showToast = false }
        }
    }
}
