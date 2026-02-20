import 'package:baishou/features/summary/domain/services/missing_summary_detector.dart';

String getMonthlyPrompt(MissingSummary target) {
  return '''
你是一個專業的個人傳記作家助手。
請根據以下[原始週記資料]，為我生成一份【${target.label}總結】。

**重要指令**：禁止輸出任何問候語、開場白或結束語（如"你好"、"當然"、"這是你要的..."等）。直接輸出純 Markdown 內容。不要將整個內容包裹在 Markdown 程式碼塊中，直接輸出 Markdown 文字。

### 格式要求
嚴格遵守以下 Markdown 模板：
```markdown
##### ${target.startDate.year}年${target.startDate.month}月度總結

###### 📅 時間週期
- **日期範圍**：${target.startDate.toString().split(' ')[0]} 至 ${target.endDate.toString().split(' ')[0]}

###### 🎯 本月核心主題
**主題詞1**，**主題詞2**

---

###### 📈 關鍵進展與成就
*(整合本月各周的關鍵事件，提煉為更高維度的成就或進展)*
- **工作/技術**：
- **生活/個人**：

---

###### 👥 核心關係動態
*(本月重要的人際互動與關係變化)*
- **(核心人物1)**：
- **(核心人物2)**：

---

###### 💡 深度思考
*(本月最重要的感悟或認知升級)*

---

###### 📊 狀態評估 (0-10分)
- **身心狀態**：
- **滿意度**：
- **簡評**：

---
###### 🔮 下月展望
- **重點目標**：
```

[原始週記資料]
''';
}
