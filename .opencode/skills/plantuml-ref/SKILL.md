---
name: plantuml-ref
description: >
  PlantUML 语法查询与参考指南。涵盖所有 UML 和非 UML 图类型（序列图、类图、活动图、用例图、
  状态图、组件图、部署图、对象图、定时图、甘特图、ER图、JSON/YAML 数据、网络图 nwdiag、
  Salt 线框图、Archimate 架构图、思维导图 MindMap、WBS 工作分解结构、Sprite 精灵图、
  Skinparam 外观参数、Creole 排版、Preprocessing 预处理、Ditaa 图、Math 数学公式、
  标准库 StdLib 等）的语法定义和具体用法。
  
  用户提及任何 PlantUML 图类型、语法关键词、布局调整、皮肤参数、箭头样式、颜色修改、
  或需要生成 PlantUML 代码时，请 ALWAYS 加载此技能进行查询。即使问题看起来简单
  （如"怎么画有颜色的 actor"），也请先查参考文档再回答——文档中通常有具体示例代码。
---

# PlantUML 语言参考指南

## 知识库位置

参考文档已从 PlantUML 官方中文参考指南 (v1.2025.0, 593 页) 提取为按章节组织的 Markdown 文件，位于：

```
Reference/plantUML/
├── ch00_封面与介绍.md
├── ch01_序列图.md          ← 序列图完整语法
├── ch02_用例图.md          ← 用例图
├── ch03_类图.md            ← 类图（关系/泛型/包/命名空间）
├── ch04_对象图.md          ← 对象图
├── ch05_活动图（旧语法）.md  ← 活动图旧版语法
├── ch06_活动图（新语法）.md  ← 活动图新版语法（条件/循环/并行/泳道/SDL）
├── ch07_组件图.md          ← 组件图
├── ch08_部署图.md          ← 部署图（包含大量箭头和样式附录）
├── ch09_状态图.md          ← 状态图
├── ch10_定时图.md           ← 定时图（时钟/二进制/模拟信号）
├── ch11_JSON数据显示效果图.md  ← JSON 数据显示
├── ch12_YAML显示效果图.md     ← YAML 数据显示
├── ch13_网络图(nwdiag).md  ← 网络拓扑图
├── ch14_线框图形界面(Salt).md  ← UI 线框图
├── ch15_架构图(Archimate).md  ← Archimate 企业架构图
├── ch16_甘特图.md          ← 甘特图（任务/里程碑/资源/日期/缩放）
├── ch17_思维导图(MindMap).md  ← MindMap
├── ch18_工作分解结构(WBS).md  ← WBS
├── ch19_数学.md            ← 数学公式（AsciiMath/JLaTeXMath）
├── ch20_实体关系图(ER).md  ← ER 图
├── ch21_通用命令.md        ← scale/title/header/footer/legend/caption/mainframe
├── ch22_Creole.md          ← Creole 排版（富文本/表格/列表/链接/表情）
├── ch23_精灵图(Sprite).md  ← Sprite 精灵图（SVG 内联/导入/变色）
├── ch24_外观参数(Skinparam).md  ← Skinparam（颜色/字体/阴影/对齐/完整参数列表）
├── ch25_预处理.md          ← 预处理（if/while/function/include/动态调用）
├── ch26_Ditaa.md           ← Ditaa 图
├── ch27_标准库(StdLib).md  ← 标准库（AWS/Azure/Kubernetes/C4/Material/Office/OSA 等）
├── ch28_附录-目录索引.md   ← TOC 索引（564 个索引条目，页号映射）
└── README.md
```

## 使用方式

1. **分类用户问题** — 用户问题涉及到哪种/哪些图类型
2. **加载对应参考文档** — 读取相关的 `.md` 文件
3. **查找答案** — 文档中有完整的 PlantUML 示例代码（`@startuml`/`@enduml` 块），直接复制参考
4. **生成回答** — 在回答中附带完整的 PlantUML 代码示例

### 示例映射

| 用户问 | 去哪个文件找 |
|--------|-------------|
| "画一个序列图，actor 是红色" | `ch01_序列图.md` → 搜索 `actor.*#red` 或 `color` |
| "类图的泛型怎么用" | `ch03_类图.md` → 搜索 `泛型` 或 `generics` |
| "新活动语法怎么画 if-else" | `ch06_活动图（新语法）.md` → 搜索 `条件` 或 `if` |
| "组件图用 UML2 标记" | `ch07_组件图.md` → 搜索 `UML2` |
| "定时图的时钟信号" | `ch10_定时图.md` → 搜索 `clock` 或 `时钟` |
| "甘特图资源分配" | `ch16_甘特图.md` → 搜索 `resource` 或 `资源` |
| "更改箭头的颜色" | `ch08_部署图.md` → 搜索 `颜色` 或 `箭头` |
| "Skinparam 修改文字大小" | `ch24_外观参数(Skinparam).md` → 搜索 `font` 或 `字体` |
| "Creole 画表格" | `ch22_Creole.md` → 搜索 `表格` 或 `Table` |
| "预处理函数传参数" | `ch25_预处理.md` → 搜索 `function` 或 `函数` |
| "不加某个库的图标" | `ch27_标准库(StdLib).md` → 搜索对应的库名 |
| "升级旧活动语法到新语法" | `ch05_活动图（旧语法）.md` + `ch06_活动图（新语法）.md` |
| "有没有 XXX 这种功能" | 先在 `ch28_附录-目录索引.md` 搜索关键词确认是否存在此功能 |

## 设计原则

- **先查文档，再回答**。不要依赖内部知识——文档中有官方示例代码，比模型记忆更准确。
- **回答带完整示例**。用户需要的是可以直接复制运行的 PlantUML 代码块（`@startuml ... @enduml`）。
- **跨章节查询**。如果问题涉及多个方面（如"给序列图的 actor 上色并改字体"），可能涉及 `ch01_序列图.md` + `ch24_外观参数(Skinparam).md`，需要读多个文件。
- **TOC 索引是快速入口**。`ch28_附录-目录索引.md` 有 564 个索引条目，不确定某个功能是否存在时，先在 TOC 中搜索关键词确认。