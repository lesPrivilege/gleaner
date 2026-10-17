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

输入记得的词：当初的要求、回复里的话、文件名或项目名。所有词都出现在同一次交付里才算匹配，分属两次对话的词不会拼成一个结果。结果打开在自身文字（你的要求、回复、会话标题）匹配到的最新一次交付上；只有文件名或项目名匹配时，打开最新一次交付。显示的也是那次交付的日期。改动搜索词后，你切换到别的交付的结果会回到匹配的那一次。

列表上方有两个菜单，分别按项目和类型筛选。项目指存放该文件的 git 仓库，同一仓库的各个 worktree 无论放在哪里都归在一起；不在 git 里的，取 agent 工作时所在的文件夹，并在该行注明“outside git”。两个项目同名时还会显示上级文件夹；文件在 worktree 里时，标出是哪个 worktree。类型共十种：Documents、Images、Video & Audio、Web Pages、Code、Data、3D & CAD、Builds & Archives、Folders、Other。界面目前只有英文，本文提到界面文字时照录原文。

详情栏依次是预览、一行说明当前显示的是哪份字节、用来拖出文件的转交卡片，以及交付这个文件的那次要求和回复。Markdown 直接在应用内渲染，其他格式多数用 Quick Look 预览。**Deliveries** 列出同一路径的每次交付，一次一行；选中一行，预览和转交卡片一起切换。**Compare** 显示两次交付之间，或某次交付与磁盘上当前文件之间的差异：文本逐行对比，图片并排显示，其他格式比较大小和哈希。两个版本只差换行符或末尾换行时，Compare 会如实说明。

## 状态

Gleaner 只陈述自己核查过的事：文件在不在、能不能读、哈希、git 状态。回复里的说法，如“测试通过”“最终版”，作为 agent 的原话引用，不会变成状态。文件在那里却读不了，绝不会被说成不在、改过或读到过。

**Gleaner 第一次怎样读到每次交付**，见 Deliveries 列表和 Details：

| 状态 | 含义 |
|---|---|
| Seen at delivery | 回复后十分钟内读到文件，且此后文件未被修改 |
| First seen later | 交付之后才第一次读到，例如补读旧日志时；可能与交付时不同。凡是标出这次交付编号的地方，都带着“first seen later” |
| Never seen | Gleaner 第一次查看时，这个路径上什么都没有 |
| Never read | Gleaner 第一次查看时路径上有东西，却读不了：打不开的文件（例如没有权限），或者不是普通文件（管道、套接字或设备） |

Gleaner 没见过或没读到的交付，会在 Gleaner 第一次读到该文件时补记为 *first seen later*，只补一次。读到过的字节不会再被改写。

**On disk now**（磁盘上的现状），见转交区，选中文件时核查：

| 状态 | 含义 |
|---|---|
| Same as delivery N | 磁盘上的文件与第 N 次交付哈希一致 |
| Unchanged since Gleaner first saw it | 文件与最新一次交付一致，但那次交付的字节是交付之后才第一次读到的 |
| Changed since delivery N | 路径上现在的东西（一个文件，或者原本交付文件的地方换成了文件夹）与任何一次交付都不一致 |
| Rolled back to delivery N | 磁盘上的文件回到了较早的第 N 次交付，而不是最新一次 |
| Back to what Gleaner first saw for delivery N | 磁盘上的文件与较早的第 N 次交付一致，但那次的字节是交付之后才第一次读到的 |
| Not among the deliveries Gleaner found | 路径上有文件，但 Gleaner 从未读到最新一次交付，无法判断是不是它 |
| Folder on disk | 交付的文件夹，显示它现在的样子；文件夹不分版本 |
| Not a regular file | 管道、套接字或设备；Gleaner 不会打开它 |
| Can't be read | 路径上有东西，但 Gleaner 打不开或读不了，无法判断是哪一版 |
| Not on disk | 文件已不在磁盘上；有存档副本时提供副本，git 历史里该路径还有文件时注明 |
| Lost | 文件不在，没有存档副本，git 里这个路径也查不到；交付记录保留 |

**列表中**，每行最多一个标记，只在需要留意时出现：*Not available* 并说明原因（never seen、never read、not on disk、can't be read、not a regular file、a folder is there now、changed），*Not on disk*，*Changed*，或 *First seen later*。绘制列表时从不读取磁盘，所以只有在应用打开后核查过的文件才会标 *Changed*。交付过不止一次的文件显示“Delivery N of M”。

**agent 日志**，见设置（Settings），需要留意时也会在列表下方用一行显示：*Read*；*Read with problems*（有未知的记录类型、有格式错误的行或比上次读时短的日志、读不了的日志或文件夹）；*Can't be read*；*Not on this Mac*。重读可能有用时会出现 Try Again，已经找到的内容照常显示。

## 转交

把详情栏里的转交卡片，或列表中的一行，拖进 Finder、聊天窗口或上传框。列表中的一行交出的版本与详情栏一致：选中的文件交出你选的那次交付，其他行交出匹配到的那次。对方拿到的是一份副本：Gleaner 复制后重新计算哈希，与所选版本一致才交出，原文件不会被移动，核对之后的改动也混不进来。磁盘上的文件已经变了，就交出存档副本。交付的文件夹按它现在的样子以副本交出，而且只在它仍是文件夹时。

文件和存档副本都没有这一版时，Gleaner 会说明为什么手里没有它的字节：从没见过或没读到，那次交付的是文件夹，文件太大没有存档，或者存档失败。磁盘上的文件是另一次交付时，提供那一次；否则，只要读得了路径上的文件，就只在“Not among the deliveries Gleaner found”的标注下提供它。无可交出的行拖不起来。文件已不在、但 git 里还有时，Gleaner 给出一条由你执行的命令，指明一个核实过包含该文件的提交：从那个提交 `git restore`，或者对已删除的 worktree，在那个提交上 `git worktree add`。Gleaner 自己从不执行。凡是 Gleaner 建议再查一次的地方，**Check Again** 都会当场核查文件并重新准备副本。

| 操作 | 快捷键 |
|---|---|
| 复制核验过的文件（焦点在列表时） | ⌘C |
| 打开核验过的文件 | ⌘O |
| Quick Look | 空格或 ⌘Y |
| 在 Finder 中显示原文件（Show in Finder） | ⇧⌘R |
| 拷贝原文件路径（Copy Path） | ⌥⌘C |
| 检查新交付 | ⌘R |
| 关闭对比 | Esc |

Show in Finder 和 Copy Path 针对原文件所在位置，那里的文件可能在交付后改过。文件已不在时，Show Folder 打开它原来所在的文件夹；那个文件夹也不在了，就如实说明。复制、打开、Quick Look 和拖拽用的都是核验过的副本。

## 交付的认定

Gleaner 只读每一轮的最终回复，回复把文件交到你手上，才收录：

- 指向本地文件的 Markdown 链接或图片，收录；标题锚点（`[guide](docs/guide.md#usage)`）不影响收录。
- 行内代码或裸路径，要带文件夹、且不带任何锚点才收录，例如 `out/report.html`；只有文件名（`App.tsx`）不收。
- 带行号锚点（`main.swift:42`、`#L42`）的是代码引用，即使写成链接也一律不收。
- 围栏代码块里的路径（没有闭合的围栏一直延续到回复末尾）、写在行内代码里的链接、带占位符的路径（`build/<name>.zip`）属于示例，不算交付。

子 agent 的回复不是给你的，跳过。这条规则从“交付”的定义推出，没有在大量真实日志上测量过；漏收或误收的例子有助于调整它。

## 读取与保存

- **读取** `~/.claude/projects` 下的 Claude Code 日志、`~/.codex` 下的 Codex 日志，以及回复里提到的文件。应用开着时监视日志文件夹，启动后才出现的也一样。通过读取 `.git` 条目找到文件所属的仓库，在仓库里只运行只读的 git 命令：文件在磁盘上时运行 `git status --porcelain --ignored`；文件已不在时运行 `git rev-parse` 和 `git log --all`，找出包含它的提交。每条命令都带 `--no-optional-locks`，git 不会改写索引；也不会运行仓库配置的任何东西：关闭 `core.fsmonitor`，不启动钩子或守护进程；关闭签名校验，`git log` 不启动签名程序；在部分克隆（partial clone）里，不去拉取克隆缺少的内容。git 比较文件时，clean filter（例如 Git LFS）仍可能运行。
- **保存**回复和要求的摘录，不存完整日志。摘录截短之前，先抹去形似密钥的字符串：API key 和访问令牌、bearer token、`key=value` 形式的密钥、URL 里的凭据，以及 40 个以上字母和数字组成、大小写字母和数字混杂的串。小写十六进制串（哈希、ID）保留。索引和存档副本放在 `~/Library/Application Support/Gleaner`。64 MB 以内的文件，第一次读到时就存一份；更大的文件只记哈希，磁盘上的文件仍与交付一致时，可以用 **Save a Copy** 存下。存档副本是交付时的原样字节，不做抹除。
- **转交副本**放在 `~/Library/Caches/Gleaner`。设置（Settings）里能看到占用并清除；清除时保留剪贴板上的那份（粘贴时还要读它），也不会动存档副本。
- **不写入**项目文件夹。Gleaner 自身不发网络请求；用 Quick Look 预览网页时，页面可能加载它引用的资源，链接只在你点击时打开。

## v0.1 的限制

- 文件夹只列出、不分版本：预览、打开和拖拽用的都是它现在的样子。
- 网页引用的图片、脚本和样式表不随页面保存，Quick Look 预览网页时也不带它们。
- 超过 64 MB 的文件，只有在磁盘上的文件仍与交付一致时选 **Save a Copy**，才会存下。没存下的大文件所在的 worktree 一旦删除，Gleaner 只能通过 git 提供它（给出一条由你执行的命令），而且前提是文件提交过；否则就丢失了。可能还要用的大文件，删除 worktree 之前先存一份。
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
- `Tests/GleanerTests`：在合成的资料库上检验应用的判断（点一下落在哪次交付上，Quick Look、Compare 和拖拽用的是哪份字节）及其措辞。

v0.1 的设计决定见 [docs/SPEC.md](docs/SPEC.md)，设计探索与裁决见 [docs/design/](docs/design/README.md)。

### Spike A

```bash
swift build -c release && .build/release/gleaner-spike
```

只读地扫描 `~/.claude/projects` 和 `~/.codex`，用与应用相同的只读 git 命令（`git status`、`git rev-parse`、`git log`）核查提到的每个文件，在 `out/` 下输出：

- `candidates.tsv`：每个候选一行，收录与否都列出，带当初的要求、证据、路径上找到了什么、交付规则是否收录（`admitted`，yes 或 no），以及留待填写的空 `label` 和 `note` 列。重新运行时保留已填的标注。路径以 `~` 开头，文字经过抹除。
- `recall-sample.md`：随机抽取的最终回复，附上每条回复里找到的候选，用来标出漏收。
- `summary.txt`：各 agent 的计数、未知的记录类型，以及提到的路径上找到了什么。
- `locators.internal.tsv`：每个候选完整的日志路径、日志行号和文件路径，供你自己核对；不要外传。

`out/` 含日志摘录，已列入 git 忽略。

参数：`--claude-root DIR`、`--codex-home DIR`、`--out DIR`、`--sample N`、`--seed N`。
