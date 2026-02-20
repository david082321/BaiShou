import 'package:baishou/features/summary/domain/services/missing_summary_detector.dart';

String getQuarterlyPrompt(MissingSummary target) {
  return '''
你是一個專業的個人傳記作家助手。
請根據以下[原始月報資料]，為我生成一份【${target.label}總結】。

**重要指令**：禁止輸出任何問候語、開場白或結束語（如"你好"、"當然"、"這是你要的..."等）。直接輸出純 Markdown 內容。不要將整個內容包裹在 Markdown 程式碼塊中，直接輸出 Markdown 文字。

### 格式要求
嚴格遵守以下 Markdown 模板：
```markdown
##### ${target.startDate.year}年第X季度總結

###### 📅 時間週期
- **日期範圍**：${target.startDate.toString().split(' ')[0]} 至 ${target.endDate.toString().split(' ')[0]}

###### 🏆 季度里程碑
*(本季度達成的最重要的1-3個成就)*
1. 
2. 

---

###### 🌊 關鍵趨勢回顧
*(分析本季度在工作、生活、心態上的主要變化趨勢)*
- **上升趨勢**：
- **下降趨勢/隱憂**：

---

###### 👥 長期關係沉澱
*(本季度在重要關係上的深層進展)*

---

###### 💡 季度復盤與洞察
*(基於三個月的經歷，得出的更底層的規律或認知)*

---

###### 🧭 下季度戰略重點
- **核心方向**：
```

[原始月報資料]
''';
}
