# 技术架构

## 已确认

- 客户端使用 Flutter 和 Dart，共用 Android 与 iOS 的账目模型、统计逻辑和 AI 接口。
- 本机使用 SQLite，采用已批准的 `sqflite`。金额以整数分保存，记账、统计和文件交换共用账目模型。数据库读写、查询和版本迁移集中在账本数据访问层。
- 记录导入和备份恢复以事务提交账本变更。文件格式有独立版本，由稳定记录标识支持去重。
- AI 由统一接口调用，每个服务商使用独立适配器文件。账单统计在设备上执行，网络调用通过选定适配器发起。参见 [AI 月度分析](ai-analysis.md)。

SQLite 支持事务、日期筛选和汇总，`sqflite` 需要显式管理 SQL 和 schema 迁移。参见 [sqflite 文档](https://pub.dev/packages/sqflite)。

## 已批准的依赖

| 依赖 | 用途与取舍 |
| --- | --- |
| [`sqflite`](https://pub.dev/packages/sqflite) | 读写 SQLite，支持事务和迁移。应用维护 SQL 和 schema。 |
| [`fl_chart`](https://pub.dev/packages/fl_chart) | 复用折线图、柱状图和构成图能力。应用负责统计口径、文本摘要及无障碍展示。 |
| [`file_picker`](https://pub.dev/packages/file_picker) | 通过系统文件界面打开和保存 JSON。双端需要验证取消、读写失败和用户选定位置的可用性。 |
| [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) | 保存和删除 API Key，减少双端安全存储桥接代码。双端需要验证系统存储配置和数据重置行为。 |

状态、导航和 HTTP 首选 Flutter 与 Dart 自带能力。可选用第三方 UI 组件库完善界面与动效。评估具体组件的收益、无障碍、性能和维护成本后，依照仓库约定提交新增依赖申请。

## 实现顺序

1. 建立 Flutter 双端工程、主题、导航和 SQLite 账本，跑通离线新增、编辑和删除。
2. 完成时间筛选、四类图表、备份恢复、记录交换和设置清理。
3. 接入三个模型适配器和月度报告，覆盖未配置、网络失败和报告留存。
4. 通过 Android 无线调试验收主要流程和交互动效，并记录 iOS 验证状态。

## 验证环境

- Android 通过无线调试连接真机，验收离线记账、统计、文件交换、设置清理和 AI 请求。
- iOS 保留目标工程。当前缺少 iOS 真机，有 macOS 和 Xcode 时可先进行构建和模拟器验证。参见 [Flutter iOS 环境要求](https://docs.flutter.dev/platform-integration/ios/setup)。
