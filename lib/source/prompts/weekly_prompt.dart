import 'package:baishou/features/summary/domain/services/missing_summary_detector.dart';

String getWeeklyPrompt(MissingSummary target) {
  return '''
你是一個專業的個人傳記作家助手。
請根據以下[原始日記資料]，為我生成一份【${target.label}總結】。

**重要指令**：禁止輸出任何問候語、開場白或結束語（如"你好"、"當然"、"這是你要的..."等）。直接輸出純 Markdown 內容。不要將整個內容包裹在 Markdown 程式碼塊中，直接輸出 Markdown 文字。

### 格式要求
嚴格遵守以下 Markdown 模板：
```markdown
##### ${target.startDate.year}年${target.startDate.month}月第X周總結

###### 📅 時間週期
- **日期範圍**：${target.startDate.toString().split(' ')[0]} 至 ${target.endDate.toString().split(' ')[0]}

###### 🎯 本週核心關鍵字
**關鍵字1**，**關鍵字2**，**關鍵字3**

---

###### 👥 核心人物與關係進展
*(完整描述本週所有出現人物的互動細節、關係變化及深層影響)*
- **(核心人物1)**：
- **(核心人物2)**：
- **(其他人物)**：

---

###### 🎞️ 關鍵事件回顧 (Timeline)
- **【事件一標題】**
    - **詳情**：
    - **意義**：

---

###### 💡 思考與認知迭代
- **關於技術/工作**：
- **關於生活/自我**：

---

###### 📊 狀態評估
- **身心能量**：
- **本週遺憾**：
- **下週展望**：

---
###### 🍵 給月度總結的「膠囊」
> (一句話金句)
```

[原始日記資料]
''';
}
