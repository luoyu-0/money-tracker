# AI 月度分析

## 已确认

- 分析只由用户主动触发，每次针对一个月份生成收支总结和规划建议。
- 首版配置 DeepSeek、通义千问（Qwen）、智谱 GLM。每家服务商的适配器独立成文件，通过统一接口切换服务商。
- 用户在应用设置中选择服务商并保存自己的 API Key。Key 存入系统安全存储，由客户端直连所选服务商，使用该用户的服务额度。
- 可分析本月至今和历史月份。设备先计算总收入、总支出、按来源或用途的汇总及上月对比。首次发送前展示待提交内容，逐笔账目和交易对方留在设备内。
- 生成的报告保存在本机，重新生成由用户主动触发。

## 配置说明

设置预填服务商的模型 ID，也可改为账号有权限访问的模型。千问默认使用阿里云百炼北京地域，其他地域和专属业务空间按控制台配置 API Host。每次生成都可先查看并确认实际发送的汇总，自定义分类名称也包含在汇总内。每个月保留最近一次成功生成的报告。生成失败时可继续查看该月原有报告。

## 服务商文档

- [DeepSeek API](https://api-docs.deepseek.com/api/deepseek-api/)
- [阿里云百炼的千问接口](https://www.alibabacloud.com/help/en/model-studio/compatibility-of-openai-with-dashscope)
- [智谱 GLM API](https://doc.gpt.cn/zh-CN/api-reference/glm-api)
