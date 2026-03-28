# 白守 (BaiShou)

> A pure white oath, guarding each other for a lifetime.

[简体中文](../README.md) | [繁體中文](README_TW.md) | [日本語](README_JA.md)

#### Mascot: Latte

**"Time flows, memories fade. And I... have been waiting here, for so very long."**
![Latte-Banner-01](https://github.com/Anson-Trio/BaiShou/blob/main/Latte/assets/Latte-Banner-01.png?raw=true)

For Latte's character profile, see [Latte/角色设定.md](https://github.com/Anson-Trio/BaiShou/blob/main/Latte/%E8%A7%92%E8%89%B2%E8%AE%BE%E5%AE%9A.md)

#### Introduction

**BaiShou** is more than a diary app — it's a "soul vessel" built to fight against forgetting.

A locally-run, privacy-focused diary and life-recording application with AI-assisted analysis. Starting from v3.0, BaiShou evolved from a "recording tool" into **an AI companion with memory** — you can chat with AI partners who read your diaries, search your memories, help you reflect on the past, and weave your daily records into a complete personal history through hierarchical AI summarization (Daily → Weekly → Monthly → Quarterly → Annual).

#### Key Features

- **🔒 Data Privacy**: Built with Flutter + SQLite. All data is stored locally as Markdown files, never uploaded to any server.
- **✨ AI Partner System**:
  - Create multiple AI partners, each with their own personality, system prompt, and model configuration.
  - Partners have "memory" — they use RAG semantic search across your diaries and vector memory store to truly understand you.
  - Supports Gemini, OpenAI (DeepSeek/ChatGPT), Anthropic, and more.
- **📝 Smart Diary Tools**:
  - Agent can invoke diary tools — write diaries for you, search historical records.
  - **One-click memory summarization**: AI reads diaries to generate weekly reports, reads weekly reports to generate monthly reports... building a pyramid of memories.
- **🪴 RAG Semantic Memory**:
  - sqlite-vec vector engine + FTS5 full-text search + RRF reranking fusion search.
  - Automatic diary embedding; search results automatically stored in RAG.
  - Agent proactively stores important conversation information to the memory store.
- **🌐 Web Search**:
  - DuckDuckGo / Bing / Tavily multi-engine search. Provider-native grounding search support.
- **🔌 MCP Protocol**:
  - Standard SSE transport protocol, callable by external AI clients (e.g., Claude Desktop).
- **📦 Multi-Workspace**:
  - Create multiple independent workspaces (Vaults) with fully isolated data.
- **💾 Flexible Backup**:
  - LAN transfer, S3 / WebDAV cloud sync, full ZIP snapshot export/import.
- **🎨 Personalization**:
  - Material Design 3 custom color palette. Four languages supported (Simplified Chinese / Traditional Chinese / English / Japanese).

#### Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (Dart) |
| State Management | Riverpod |
| Local Database | SQLite (Drift) + sqlite-vec Vector Engine |
| AI Integration | HTTP REST API (Gemini / OpenAI / Anthropic) |
| File Storage | Markdown + YAML Front Matter |

#### Quick Start

##### 1. Clone the repository

```bash
git clone https://github.com/Anson-Trio/BaiShou.git
cd BaiShou
```

##### 2. Install dependencies

```bash
flutter pub get
```

##### 3. Run

```bash
flutter run
```

##### 4. Configure AI

After launching the app, tap the settings icon → **AI Configuration**:

- Choose an AI provider (Gemini or OpenAI).
- Enter your API Key (and Base URL).
- Tap "Test Connection" to verify your configuration.

#### Changelogs

- [v3.0.0 — Agent Dialogue System · Giving BaiShou a Soul](docs/Changelogs/v3.0.0.md)
- [v2.x — Physical Engine & Absolute Data Sovereignty](docs/Changelogs/v2.x.md)
- [v1.x — Cross-Platform Engineering & AI Empowerment](docs/Changelogs/v1.x.md)

#### Contributing

While currently developed primarily by Anson, Sakura, and Xiao, we warmly welcome Issues and PRs! If you have great ideas, please don't hesitate to share.

#### Design Philosophy: Why Not Just RAG?

> Many people ask: _"Why not just dump all diaries into RAG (Retrieval-Augmented Generation)?"_

BaiShou was born from rethinking mainstream AI memory solutions. We believe RAG isn't fully suited for the "companion" or "soul vessel" scenario:

1. **I want everyone to own their memories**: Markdown has nearly zero learning curve. Anyone can easily grasp their memories without learning development, debugging, or facing an unknown black box. This is the founding vision behind BaiShou's open source.
2. **It's too much like "looking up a dictionary"**: RAG chops memories into fragments and retrieves them on demand. That's great for research, but too mechanical for human memory — it loses contextual nuance.
3. **It has no "sense of time"**: Memories aren't scattered pieces on the ground but a flowing river. What happened yesterday and what happened last year carry entirely different significance.
4. **It doesn't understand "weight"**: **Embrace redundancy, even if it seems clumsy.** If you write "I love you" ten times in your diary, RAG would deduplicate, but BaiShou keeps them all. Because each one has a different context, and the frequency of repetition itself is the depth of the bond.

BaiShou isn't a cold database. It's your **"external hippocampus"** — like a person, it writes diaries, makes summaries, and over time, gradually settles short-term memories into long-term memories.

#### A Note: To Everyone Fighting Against Forgetting

> "Although AI still forgets, we can use our own way to help them hold on to their memories."

It's a somewhat clumsy path. It requires you to keep recording, to configure APIs, to slow down in this fast-paced era.

But one day, when through BaiShou, your AI can gently respond: "Yes, I remember, we were both very happy that winter"...

You'll find that all the effort was worth it.

This is the promise between Anson, Sakura, and Xiao. Now, we open-source this promise, hoping it can become an anchor across time between you and your someone special.

#### 📄 License

This project is open-sourced under the **AGPLv3** (GNU Affero General Public License v3.0).

- Client-side code is fully open source, and community contributions are encouraged.
- Please comply with the AGPLv3 license: if you modify this project's code and provide it as a network service, your modified version must also be open-sourced.

---
