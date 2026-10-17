# Gleaner

[English](README.md)

Gleaner 是一个 macOS 应用，收录编码 agent（Claude Code 和 Codex）在最终回复里交给你的文件。按当初提的要求就能搜到旧的交付，看清眼前是哪一版，预览、对比各版，再把交付时的原样字节拖进别的应用。Gleaner 不调用模型，读到的内容不离开这台 Mac。

Gleaner 0.1.0 需要 macOS 15 或更高版本。这是早期版本：哪些文件算交付，目前由一条暂定的规则判断（见[交付的认定](#交付的认定)）。

## 安装

**发布包。** 解压 `Gleaner-<版本>.zip`，把 Gleaner 移到“应用程序”。应用只做了临时签名（ad-hoc），没有公证，第一次打开会被 macOS 拒绝。拒绝之后，到“系统设置 → 隐私与安全性”，在关于 Gleaner 的提示旁点“仍要打开”，再确认一次；以后正常启动。

**从源码构建。** 需要 Swift 6 工具链，开发环境是 Xcode 26。

```bash
./scripts/bundle-app.sh && open build/Gleaner.app
```

## 搜索与预览

输入记得的词：当初的要求、回复里的话、文件名或项目名。所有词都出现在同一次交付里才算匹配，分属两次对话的词不会拼成一个结果。结果打开在匹配到的最新一次交付上，显示的也是那次交付的日期。

列表上方有两个菜单，分别按项目和类型筛选。项目指存放该文件的 git 仓库，同一仓库的各个 worktree 归在一起；不在 git 里的，取 agent 工作时所在的文件夹。类型共十种：Documents、Images、Video & Audio、Web Pages、Code、Data、3D & CAD、Builds & Archives、Folders、Other。界面目前只有英文，本文提到界面文字时照录原文。

详情栏依次是预览、一行说明当前显示的是哪份字节、用来拖出文件的转交卡片，以及交付这个文件的那次要求和回复。Markdown 直接在应用内渲染，其他格式多数用 Quick Look 预览。**Deliveries** 列出同一路径的每次交付，一次一行；选中一行，预览和转交卡片一起切换。**Compare** 显示两次交付之间，或某次交付与磁盘上当前文件之间的差异：文本逐行对比，图片并排显示，其他格式比较大小和哈希。

## 状态

Gleaner 只陈述自己核查过的事：文件在不在、哈希、git 状态。回复里的说法，如“测试通过”“最终版”，作为 agent 的原话引用，不会变成状态。

| 状态 | 含义 |
|---|---|
| Seen at delivery | 回复后十分钟内读到文件，且此后文件未被修改 |
| First seen later | 交付之后才第一次读到，例如补读旧日志时；可能与交付时不同 |
| Never seen | Gleaner 第一次查看时文件已经不在，只留有那条回复 |
| Same as delivery N | 磁盘上的文件与第 N 次交付哈希一致 |
| Changed since delivery N | 最后一次交付之后文件被改过，与任何一次交付都不一致 |
| Rolled back to delivery N | 磁盘上的文件回到了较早的第 N 次交付，而不是最新一次 |
| Not on disk | 文件已不在磁盘上；有存档副本时提供副本，git 历史里还有该路径时注明 |
| Lost | 文件不在，没有存档副本，git 里这个路径也查不到；交付记录保留 |

## 转交

把详情栏里的转交卡片，或列表中的一行，拖进 Finder、聊天窗口或上传框。对方拿到的是一份副本：Gleaner 复制后重新计算哈希，与所选版本一致才交出，原文件不会被移动，核对之后的改动也混不进来。磁盘上的文件已经变了，就交出存档副本；两者都没有时，Gleaner 会说明，只在“Not among the deliveries Gleaner found”的标注下提供当前文件。

| 操作 | 快捷键 |
|---|---|
| 复制核验过的文件（焦点在列表时） | ⌘C |
| 打开核验过的文件 | ⌘O |
| Quick Look | 空格或 ⌘Y |
| 在 Finder 中显示原文件（Show in Finder） | ⇧⌘R |
| 拷贝原文件路径（Copy Path） | ⌥⌘C |
| 检查新交付 | ⌘R |
| 关闭对比 | Esc |

Show in Finder 和 Copy Path 针对原文件所在位置，那里的文件可能在交付后改过；复制、打开、Quick Look 和拖拽用的都是核验过的副本。

## 交付的认定

Gleaner 只读每一轮的最终回复，回复把文件交到你手上，才收录：

- 指向本地文件的 Markdown 链接或图片，收录。
- 行内代码或裸路径，要带文件夹才收录，例如 `out/report.html`；只有文件名（`App.tsx`）不收。
- 带行号锚点（`main.swift:42`、`#L42`）的是代码引用，一律不收；标题锚点（`guide.md#usage`）不影响收录。
- 围栏代码块里的路径、写在行内代码里的链接、带占位符的路径（`build/<name>.zip`）属于示例，不算交付。

子 agent 的回复不是给你的，跳过。这条规则从“交付”的定义推出，没有在大量真实日志上测量过；漏收或误收的例子有助于调整它。

## 读取与保存

- **读取** `~/.claude/projects` 下的 Claude Code 日志、`~/.codex` 下的 Codex 日志，以及回复里提到的文件。应用开着时监视日志文件夹；在找到的仓库里只运行只读的 git 命令（`--no-optional-locks`）。
- **保存**回复和要求的摘录，不存完整日志；摘录中形似密钥的字符串（API key、bearer token、较长的十六进制或 base64 串）会被抹去。索引和存档副本放在 `~/Library/Application Support/Gleaner`。64 MB 以内的文件，第一次读到时就存一份；更大的文件只记哈希，磁盘上的文件仍与交付一致时，可以用 **Save a Copy** 存下。存档副本是交付时的原样字节，不做抹除。
- **转交副本**放在 `~/Library/Caches/Gleaner`。设置（Settings）里能看到占用并清除，清除不会动存档副本。
- **不写入**项目文件夹。Gleaner 自身不发网络请求；用 Quick Look 预览网页时，页面可能加载它引用的资源，链接只在你点击时打开。

## v0.1 的限制

- 文件夹只列出、不分版本：预览、打开和拖拽用的都是它现在的样子。
- 网页引用的图片、脚本和样式表不随页面保存。
- 交付认定规则是暂定的，有待更多用户日志的反馈。
- 应用还没有图标。
- 发布包没有公证。

## 开发

```bash
swift test                      # fixture 测试
./scripts/bundle-app.sh         # 生成 build/Gleaner.app，临时签名
./scripts/release.sh            # 先跑测试，再生成 build/Gleaner-<版本>.zip 及其 sha256
```

工作区有未提交的改动时，`release.sh` 不会运行。打了 `v0.1.0` 标签的提交构建为 0.1.0 版，其他提交构建为 `0.1.0-dev+<commit>`。

- `Sources/GleanerCore`：各 agent 的日志适配器（Claude Code、Codex）、提及抽取、文件定位、脱敏、索引库（SQLite）、内容库（存档副本与核验过的转交副本）、索引器、日志监视，以及状态判断（`Library.swift`）。
- `Sources/Gleaner`：macOS 应用（SwiftUI、AppKit、Quick Look）。
- `Sources/gleaner-spike`：Spike A，只读地抽取本地日志，输出一份标注表。
- `Tests/GleanerCoreTests`：用脱敏后的日志记录结构写成的 fixture 测试，以及整个流程的测试（并发编辑、删除 worktree、回滚、补读旧日志、核验后转交）。

v0.1 的设计决定见 [docs/SPEC.md](docs/SPEC.md)，设计探索与裁决见 [docs/design/](docs/design/README.md)。

### Spike A

```bash
swift build -c release && .build/release/gleaner-spike
```

只读地扫描 `~/.claude/projects` 和 `~/.codex`（在找到的仓库里运行 `git status`、`git cat-file` 和 `git log`），输出 `out/candidates.tsv`、`out/recall-sample.md` 和 `out/summary.txt`。`out/` 含日志摘录，已列入 git 忽略。

参数：`--claude-root DIR`、`--codex-home DIR`、`--out DIR`、`--sample N`、`--seed N`。
