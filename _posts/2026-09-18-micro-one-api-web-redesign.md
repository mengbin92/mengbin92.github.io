---
title: "先量再改：一次有审计底稿的 UI 重设计"
date: 2026-09-18T12:00:00+08:00
description: "这次重设计的起点不是“界面不好看”，是一件更实际的事：字体没覆盖中文。"
tags: ["Micro-One-API", "前端", "架构"]
categories: ["architecture"]
draft: false
---

## 0. 一个差点被我当成"样式问题"的许可证问题

这次重设计的起点不是"界面不好看"，是一件更实际的事：**字体没覆盖中文。**

前端原本用 Geist Variable。它是 OFL-1.1 开源字体，拉丁字符很漂亮，但**不完整覆盖简体中文**。所以在中文界面上，中文部分实际上落到了不确定的系统回退字体上。

而这带来一个更隐蔽的问题：logo 的 SVG 里声明了 Inter 加系统回退，但 Inter 并没有被打包。**单独打开那个 SVG 文件，字是完全不可控的。**

如果只是"看起来不好看"，我可以慢慢改。但字体是可分发资产，这里牵涉两件事：

1. 换字体要履行许可证的随附义务（"开源"不等于可以删掉版权声明）；
2. 自托管和外部 CDN 引用的合规含义不一样。

所以我把它定义成这次改造的 Phase A：**先解决字体和许可，再谈视觉。**

最终选的是 **Noto Sans SC Variable**——覆盖简繁中文加拉丁，字重 100–900，SIL OFL 1.1，可以随 Web 应用自托管和再分发。

依赖替换很干净：

```bash
cd web
npm uninstall @fontsource-variable/geist
npm install @fontsource-variable/noto-sans-sc
```

```css
@import "@fontsource-variable/noto-sans-sc/wght.css";

@theme inline {
  --font-sans: "Noto Sans SC Variable", ui-sans-serif, system-ui, sans-serif;
  --font-heading: var(--font-sans);
}
```

但实施要求里我给自己加了四条硬约束：

- **把安装包里的 `LICENSE` 原文复制成 `web/public/licenses/NotoSansSC-OFL-1.1.txt`**，不得摘要或改写。
- **生产运行时不得请求 Google Fonts、Fontsource CDN 或 jsDelivr。** 字体由 Vite 打包到同源静态资源。
- **不预加载全部 CJK 分片**，只在真实首屏数据证明有收益时才预加载必要资源。
- **UI 常用字重限定 400/500/600/700**，不再依赖 900 来制造层级。

第二条和第三条是一对：CJK 字体分片很多，全量预加载会把首屏拖垮。所以我选了"同源打包、浏览器按需取分片"这个默认行为，而不是预先优化。

现在的验收命令是一条 grep：

```bash
! rg -n "Geist|Inter|SF Pro|-apple-system|BlinkMacSystemFont" \
  web/src web/public web/package.json web/package-lock.json
```

**用 grep 的退出码做验收，而不是靠肉眼看页面。** 我后面会讲为什么这条很重要。

---

## 1. 先量，再改：那份量化基线

这次改造和我做过的大多数 UI 调整不一样的地方是：**动手之前我先数了一遍。**

数出来的东西写进了文档，统计范围是 `web/src/**/*.{tsx,css}`：

| 项目 | 实测结果 | 说明 |
|---|---:|---|
| `ring-1 ring-slate-200` | 36 处 / 13 个文件 | 30 个 `Card`，6 个普通 `div` |
| `slate-*` | 440 处 | 需按语义逐处判断，禁止盲目全局替换 |
| `font-black` | 73 处 / 15 个文件 | 大多数应降为 600/700，但数据强调可保留个例 |
| `rounded-lg` | 156 处 | 表单、按钮、表格容器含义不同，不能一刀切 |
| 图表硬编码 hex | 多处 | 集中在 Dashboard、CostAnalysis、CostCharts、HealthCharts |
| 当前 Web 字体 | Geist Variable | OFL-1.1，但不完整覆盖简体中文 |
| Logo 字体声明 | Inter + 系统回退 | 字体未嵌入，独立打开 SVG 时结果不可控 |

而且我把复核命令也写进了文档：

```bash
rg -n "ring-1 ring-slate-200" web/src -g '*.tsx'
rg -o "slate-[0-9]+" web/src -g '*.tsx' | wc -l
rg -l "font-black" web/src -g '*.tsx' | wc -l
rg -o "rounded-lg" web/src -g '*.tsx' | wc -l
```

这么做有两个我当时没想到的好处：

**第一，"444 处 slate"这个数字直接否掉了我原本的计划。** 我原来的想法是"全局替换 slate 为语义色"。数出来 440 处之后我就知道那不可行——里面既有文字色、又有边框色、还有背景色，语义完全不同。**一个"大数字"有时候不是任务清单，而是一个警告。**

**第二，`ring-1 ring-slate-200` 那 36 处里，有 6 处不是 Card。** 这个发现救了我一次：我的第一版迁移方案是"把所有带这个 class 的元素换成 Card 表面样式"，那 6 处会被误伤——它们是表格容器和信息标签，套上 Card 的圆角和内边距会很难看。

文档里把这 6 处单独列了出来：

> - **6 个普通 div**：不能回落到 Card 默认值，需显式改为语义表面。
>   - PricingPage 的信息标签：`rounded-xl border border-border bg-card shadow-surface-sm`。
>   - UsagePage、OrdersPage、PaymentOrdersPage 与 ReconciliationPage 的 5 个表格容器：`overflow-x-auto rounded-2xl border border-border bg-card shadow-surface-sm`。

**如果不先数，我会在改到第 30 个文件的时候才发现有 6 个特例，然后回头返工。**

---

## 2. 迁移的关键：删掉视觉 class，但保留布局 class

相位 C 的标题就叫"迁移 36 处旧表面样式"，但真正的重点在括号里：

> **先区分元素类型，禁止删除整个 `className`。**

具体做法：

- **30 个 Card**：只移除 `rounded-* border-0 bg-white shadow-sm ring-1 ring-slate-200 dark:bg-card dark:ring-white/10` 这些**旧视觉 token**；保留 `min-h-*`、`w-full`、`flex`、`xl:col-span-*` 这些**布局类**。
- **6 个普通 div**：显式指定语义表面，不套用 Card。

为什么强调这一点？因为一个 `className` 字符串里混着两类完全不同职责的 class：

```tsx
// 视觉：圆角、边框、背景、阴影、描边
rounded-lg border-0 bg-white shadow-sm ring-1 ring-slate-200

// 布局：最小高度、宽度、弹性、栅格跨列
min-h-[120px] w-full flex xl:col-span-3
```

**"删掉整个 className"看起来更彻底、更干净，但会把布局一起删掉。** 而且这种错误不会报错，只会让某个卡片突然塌掉或者栅格错位——你得一个个页面点过去才发现。

我在文档里把这条写成了显式禁令，而不是"注意保留布局类"这种提醒。**禁令可执行，"注意"不可执行。**

### 2.1 验收也用 grep 的退出码

同样在文档里：

> 验收命令使用 `rg` 的退出码，不使用会逐文件输出计数的 `grep -rc`：

```bash
! rg -n "ring-1 ring-slate-200" web/src -g '*.tsx'
```

`!` 加 `rg` 的退出码：**找到任何一处就失败。**

用 `grep -rc` 的话，输出是一堆 `文件:0 文件:1 文件:0`，你还得自己判断有没有非零。而 `! rg` 直接给你一个是/否。

**"迁移完成"必须是一个可自动判断的命题，否则它永远只是"我觉得改得差不多了"。**

---

## 3. 三个我认为最值的技术决定

### 3.1 Tailwind v4 的圆角 token 必须放在 `@theme`

这是一个我改错过的地方，文档的 v4 审查结论第一条就记着（第 3 条）：

> **Tailwind v4 圆角 token 位置错误**：`--radius-sm` 等必须在顶层 `@theme` 中定义，写进 `:root` 不会更新 `rounded-*` 工具类。

Tailwind v4 里有两类自定义值，位置要求不一样：

| 值 | 放哪 | 原因 |
|---|---|---|
| 会生成工具类的（圆角、阴影、字体、缓动） | 顶层 `@theme inline` | v4 在编译期据此生成 `rounded-*` 等工具类 |
| 运行时才变的颜色值 | `:root` / `.dark` | 主题切换时被 CSS 变量覆盖 |

**把 `--radius-*` 写进 `:root`，`rounded-2xl` 不会变成你的值。** 不报错，只是没生效——而"没生效"在视觉上很难判断，因为默认值看起来也不难看。

所以最终结构是这样：

```css
@theme inline {
  --font-sans: "Noto Sans SC Variable", ui-sans-serif, system-ui, sans-serif;
  --font-heading: var(--font-sans);
  --shadow-surface-sm: var(--surface-shadow-sm);
  --shadow-surface-md: var(--surface-shadow-md);
  /* 圆角、缓动同理 */
}
```

```css
:root {
  --muted-foreground: #6E6E73;
  --color-muted-foreground: var(--muted-foreground);
  /* 颜色的运行时值 */
}
```

文档里还加了一条约束：**不要在 `.dark` 内嵌套 `@theme`。** 因为嵌套会让"这个 token 在深色下是否重新生成工具类"变得无法推理。

### 3.2 中文不该用负字距

这一条我一开始是反着做的，文档里记着：

> **中文排版被过度压缩**：全局给 `h1/h2/h3` 设置负字距会伤害中文可读性。本版只在拉丁字符占主导的展示标题上按需使用 `tracking-tight`。

负字距（`tracking-tight` / `letter-spacing: -0.02em`）在现代 UI 里很常见——它确实让大号拉丁标题显得更紧凑、更"设计感"。但**中文字形是方块字，字面本身就占满字身框，收紧字距会让笔画粘连。**

所以规则改成：

> - 不全局修改 `h1/h2/h3` 字距。中文标题默认 `tracking-normal`；拉丁字符占主导的展示标题可局部使用 `tracking-tight`。

**按"这个标题主要是中文还是拉丁"分别决定，而不是按"标题的层级"决定。**

这条我认为是这次改造里最有价值的一个认知：**我把一套拉丁排版的经验直接套到中文上，而且还觉得它更专业。** 判断的依据不应该是"这看起来更现代"，而是"这种文字的字形特点是什么"。

### 3.3 `transition-all` 是个陷阱

> **动效范围过宽**：`transition: all` 可能意外动画布局属性，且缺少 `prefers-reduced-motion`。本版改为属性级过渡并补充减弱动效策略。

`transition-all` 写起来最省事，但它会动画**所有**可动画属性——包括 `width`、`height`、`padding`、`margin` 这些会触发布局重算的属性。

**一个"颜色变化"的过渡，实际可能连带触发每帧的布局计算。**

所以规则是：

> - 禁止新增 `transition-all`。颜色变化用 `transition-colors`，位移/缩放用 `transition-transform`，阴影用 `transition-shadow`。
> - 只在 `motion-safe:` 下启用按压缩放、微光和弹窗缩放；`motion-reduce:` 下移除非必要动画并把时长降为 0。

第二条是**动效的可访问性**：前庭功能障碍的用户会因为按压缩放、弹窗缩放这类动画感到不适。`prefers-reduced-motion` 是系统级偏好，用它来降级。

而且我把它写成了 Tailwind 的 `motion-safe:` / `motion-reduce:` 变体，而不是手写媒体查询——**用变体意味着每个用到动效的地方都会自然带上这个前缀，而手写查询很容易漏。**

---

## 4. 对比度：那两个不合格的颜色

这是我觉得最不体面的一条，因为它是"我一直以为没问题"的地方。

文档的审查结论里写着：

> **对比度声明不完整**：`#007AFF` 上的白色小字约为 4.02:1，不满足 WCAG AA 普通文本 4.5:1；11px 的 `#86868B` 也不合格。本版改用可访问的交互色与最小字号。

两个问题：

**`#007AFF` 上的白色小字是 4.02:1。** WCAG AA 要求普通文本至少 4.5:1。4.02 不是"差一点"，是**不合格**。而这个蓝是很典型的主色选择。

**11px 的 `#86868B` 不合格。** 小字本来就需要更高的对比度（因为笔画更细），而 `#86868B` 这种灰色配上 11px，实际可读性很差。

修复的方式是两条：

> - 正文与表格内容不低于 14px；12px 只用于辅助元数据且必须使用 `text-muted-foreground`，不得使用低对比的 `#86868B`。
> - 逐状态抽查而非只测静态页面。

第二条我特意加的。**对比度检查容易做成"测一下主色"，但真正的问题往往在状态上**：hover 之后、disabled、深色模式、图表上的标签。所以验收要求是逐状态抽查。

这里有一个我当时没意识到的连带影响：**把最小字号从 11px 提到 14px，会让某些紧凑布局溢出。** 所以字号的改动和布局的调整是耦合的，不能只改字号就完事。

---

## 5. 我已经做到哪了（写完这篇的时候刚数的）

文档里定的是目标，我用 grep 数了当前的实际状态：

| 项目 | 基线 | 现在 |
|---|---:|---:|
| `Geist` / `Inter` 引用 | 存在 | **0** |
| `ring-1 ring-slate-200` | 36 处 / 13 文件 | **0** |
| `transition-all` | 多处 | **0** |
| `slate-*` | 440 处 | **240 处** |
| `font-black` | 73 处 / 15 文件 | **14 处 / 1 文件** |
| 10px / 11px 字号 | 多处 | **4 处** |
| `motion-reduce` / `prefers-reduced-motion` | 无 | **11 个文件** |

字体和许可证这一块是干净的：

```bash
web/public/licenses/NotoSansSC-OFL-1.1.txt   ← 存在
web/package.json: "@fontsource-variable/noto-sans-sc": "^5.3.0"
```

### 5.1 `font-black` 剩下的 14 处在一个文件里

这个是数出来的、而不是感觉出来的：

```
src/pages/RechargePage.tsx:112  text-3xl font-black text-blue-600
src/pages/RechargePage.tsx:119  text-4xl font-black text-orange-500
src/pages/RechargePage.tsx:137  text-lg font-black text-slate-950 dark:text-white
...
```

14 处全在 `RechargePage.tsx`，而且它同时还在用硬编码色（`text-blue-600`、`text-orange-500`、`#1677ff`）和旧的 `slate-950` / `slate-700`。

我去查了迁移清单——**`RechargePage` 根本不在里面。**

文档里 Phase C 的文件清单是 13 个文件：

```
AdminRoute.tsx / ChannelHealthPage.tsx / CostAnalysisPage.tsx / OverviewPage.tsx /
PaymentOrdersPage.tsx / ReconciliationPage.tsx / ApiGuidePage.tsx / DashboardPage.tsx /
OrdersPage.tsx / PlaygroundPage.tsx / PricingPage.tsx / ProfilePage.tsx / UsagePage.tsx
```

**没有 `RechargePage.tsx`。** 所以这 14 处不是"没改完"，而是**这一页从来没有被纳入范围**。

这个发现让我对那份基线清单的评价变了：它看起来很像一次彻底的清点，但它其实只覆盖了"我当时想起来的页面"。**用清单管理迁移的代价是，清单之外的东西会以"看起来已经完成了"的样子留下来。**

### 5.2 剩下 4 处小字号里也有一个类似的问题

```tsx
UsageAuditPanel.tsx:284  text-[10px] text-muted-foreground   ← 合规（辅助元数据）
UsageAuditPanel.tsx:342  text-[10px] text-muted-foreground   ← 合规
UsagePage.tsx:182        text-[10px] ... text-amber-300      ← 需要判断
UsagePage.tsx:185        text-[10px] ... text-rose-300       ← 需要判断
```

前两处用的是 `text-muted-foreground`，符合"12px 以下只用于辅助元数据"的规则。后两处是彩色徽章，属于"状态标签"，得单独判断对比度。

**这就是"逐状态抽查"和"grep 一遍"的区别**：grep 只能告诉你"这里有 10px 的字"，不能告诉你它合不合规。

---

## 6. 我在这套流程里学到的事

如果只留三条：

**第一，动手之前先数一遍，而且把复核命令写进文档。**

数一遍的价值不在于知道"有 440 处"，而在于**发现"440 处里有 36 处是特例"**。复核命令的价值在于：三个月后我不用回忆当时是怎么数的，直接跑一遍就行。

**第二，把验收写成可自动判断的命题。**

`! rg -n "ring-1 ring-slate-200"` 这个形式比"确认旧样式已清理"强得多。前者跑一下就出结论，后者要靠人判断"清干净了没有"。

**第三，把"为什么"和"现状"分开写。**

这次文档里有两类内容：

- **规则类**（为什么中文不用负字距、为什么禁止 `transition-all`、为什么圆角 token 要放 `@theme`）——这类不会过期。
- **现状类**（现在有多少处、哪些文件、多少 px）——这类会过期，而且过期后极具误导性。

我在第 15 篇提过 `platform/cache` 里那段已经过期的注释。这次我刻意把有数字的部分都标了统计范围和复核命令，让它至少能被验证。

---

## 7. 还没解决的

**第一，`RechargePage.tsx` 完全没迁移。** 14 处 `font-black`、硬编码色、`slate-*` 都在这一页。

**第二，`slate-*` 还剩 240 处。** 从 440 降到 240 主要是跟着 36 处表面样式一起清掉的。剩下的是逐处判断的活，文档里明确写了"禁止盲目全局替换"，所以只能慢慢来。这一块的进度我心里没有数——**因为没有像 `ring-1 ring-slate-200` 那样可以一键判断的验收命令。**

**第三，图表配色只改了一部分。** 文档要求 Recharts 的 `stroke`、`fill`、渐变 stop、坐标轴、网格线分别使用 `var(--chart-N)` / `var(--chart-label)` / `var(--chart-grid)`，还要求多序列图除颜色外用图例或线型区分（照顾色觉差异）。我先改了集中那几处，散落的没系统清完。

**第四，深色模式只做了静态抽查。** 逐状态检查这个要求在深色模式下工作量翻倍，我没有全做完。

**第五，`Noto Sans SC` 的首屏体积我没有对比记录。** 文档里要求"字体资源使用长期缓存，首屏传输量与改造前基线对比并记录"，我只确认了它不再请求第三方 CDN，没有留下改造前后的传输量对比。

---

## 8. 下一篇

下一篇讲 Playground：一个"在浏览器里直接调模型"的页面，最麻烦的部分不是聊天界面，而是**API Key 怎么才能不落到任何地方**。包括一次性内存交接、为什么不能用已有的 admin 请求客户端、以及 SSE 解析里两个我自己踩到的坑。

[《浏览器里直接调模型：怎么让 API Key 不落到任何地方》](/2026-09-18-micro-one-api-web-playground/)
