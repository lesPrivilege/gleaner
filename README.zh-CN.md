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

输入记得的词：当初的要求、回复里的话、文件名、项目名，或作品所在合集的名字。所有词都出现在同一次交付里才算匹配，分属两次对话的词不会拼成一个结果。结果打开在自身文字（你的要求、回复、会话标题）匹配到的最新一次交付上；只有文件名、项目名或合集名匹配时，打开最新一次交付。显示的也是那次交付的日期。结果会标出它所在的合集。改动搜索词后，你切换到别的交付的结果会回到匹配的那一次。文件也能按它在项目内的各级文件夹找到（`series covers` 能找到 `series/assembly/covers/cmp.svg`）；文件名、文件夹、项目或合集包含全部搜索词的结果排在前面，只在请求或回复里提到的排在后面。随文件夹交付的文件，按它的文件名、所在文件夹和项目找到；回复里的话找到的是那个文件夹。搜索只覆盖交付和你收录的文件：不读文件内容，会话期间只被观察到的文件也搜不到，它们在项目的 Observed 下。

侧栏列出 All Deliveries、To Review、每个项目及其中的合集，以及 Sources。项目指存放该文件的 git 仓库，同一仓库的各个 worktree 无论放在哪里都归在一起；不在 git 里的，取 agent 工作时所在的文件夹，用文件夹标记而不是仓库标记表示。两个项目同名时还会显示上级文件夹；文件在 worktree 里时，标出是哪个 worktree。在项目里搜索，只搜这个项目。结果上方的菜单按类型筛选，共十种：Documents、Images、Video & Audio、Web Pages、Code、Data、3D & CAD、Builds & Archives、Folders、Other。界面目前只有英文，本文提到界面文字时照录原文。

详情栏仿照 Finder 的预览栏：最上面是文件本身，带着它自己的图标，可以拖出或打开；一行说明它带的是哪份字节、Gleaner 是否核验过；然后是预览；接着是 **Review**，列出你的结论，最新一条备注完整显示；再是 **Information**：你的要求、交付这个文件的那次回复、agent（用它自己的标志）和会话、时间、磁盘上的现状，以及位置。Markdown 直接在应用内渲染，其他格式多数用 Quick Look 预览。**Versions** 列出同一路径的每次交付，一次一行；选中一行，文件、预览和转交一起切换。一切如常的状态只显示一个标记；需要留意的用一两个词说明，完整的句子在 ⓘ 后面。**More Info** 保留路径、哈希和会话日志。**Compare** 显示两次交付之间，或某次交付与磁盘上当前文件之间的差异：文本逐行对比，图片并排显示，其他格式比较大小和哈希。两个版本只差换行符或末尾换行时，Compare 会如实说明。

## 项目与作品

打开一个项目，先看到它的概览：它是什么、为什么归在这里，最近交付的作品，Gleaner 建议合并的文件，再按所在文件夹列出每件作品：人打开的在程序读取的之前，最新的在前。回复交付一个文件夹时，里面的每个文件都是随该文件夹交付的作品，列在它自己所在的文件夹下；同类这样的文件挤满一个文件夹时，折叠成一行并标出数量，而回复逐个点名的文件从不折叠。文件的详情写明它随哪个文件夹交付、对应哪条回复；文件夹的详情给出其中的文件数，或说明为什么不展开（主目录、卷或云盘、它们下面直接的文件夹、链接、隐藏文件夹、缓存或软件包及其中的文件夹、项目自己的文件夹）。交付过不止一次的作品可以展开，列出每次交付和当时的请求；git 之外的项目和你自己建的项目默认展开，git 仓库默认收起。用 ← 和 → 收起或展开。一件作品是一个文件，或你确认属于同一件作品的几个文件，比如从 draft 改名为 final 的报告；详情里列出每个文件的每次交付。Gleaner 从不自行合并文件，只在有可查证的理由时提出建议：后一个文件带着前一个文件最后的同样字节出现，而前一个已经不在原来的路径；或者同一文件夹里两个名字只差一个版本标记（`v2`、`rev 3`、`draft`、`final`、`(1)`；日期或单纯的数字表示另一份文件）。选 **Join** 或 **Keep Apart**；选了 Keep Apart 之后，Gleaner 不再为那个文件提出建议。Edit › Undo 可以撤销一次合并、一次 Keep Apart 或一次移动。

作品详情里的 **Project** 说明它为什么归在这个项目（文件所在的仓库、agent 工作时所在的仓库，或 git 之外的文件夹），并提供 **Move to Project…**（移到另一个项目，或你新建的项目）和 **Join With Another File…**。侧栏里项目的菜单可以把一个推导出的项目显示在另一个项目之内。这些决定只改变 Gleaner 的呈现方式，不改动任何文件、交付或状态；重新读取日志也会保留。**Sources → Corrections** 逐条列出，每条可 Undo，也可 Undo All。

会话旁边的 **Copy Resume Command** 复制 `claude --resume <id>` 或 `codex resume <id>`，连同进入会话起始文件夹的 `cd`，在终端里继续那次会话。只在会话日志和那个文件夹都还在时提供；否则它会说明为什么无法继续。**Delivered With** 能到达那次回复提到的每个文件。

## 审阅

**合集**（collection）按你心里的样子把作品归在一起，比如一个系列和它的各集；合集里还可以再放合集，只能嵌套一层。用 **New Collection**（⇧⌘N，或侧栏里项目的菜单）新建，直接在原处命名，然后把列表里的行拖到它上面，或者在行的菜单里选 **Add to Collection**，一次选多行也可以。一件作品最多属于一个合集，所以对已在某个合集里的作品，这条命令写作 **Move to Collection**。**New Collection from These** 把窗口里已经显示在一起的一组恰好收进一个新合集：项目概览里的一个文件夹、一次会话观察到的文件、折叠的一行、审阅页上并排的文件、同一条回复一起交付的文件，或一次搜索的结果；已在某个合集里的作品会离开原合集，命令会说明这一点；一次 Undo 就能撤回。项目概览最先列出它的合集，各自标出待审的数量，侧栏也在项目下列出；作品那一行的帮助提示写明它所在的合集。文件留在原处；Rename、Delete 以及其他每个决定都可以用 Edit › Undo 撤销，并列在 Sources → Corrections 里。

合集的**审阅页**把其中每件作品都直接从磁盘上的文件呈现出来：视频就地播放，音频在一行播放条里播放，图片按各自的比例并排，文档直接渲染，程序读取的文件收在 Other Files 里。同一文件夹里只有扩展名不同的文件放在一起（`ov-4x3.svg` 放在 `ov-4x3.png` 旁边）；其余每个文件都各自呈现。**Review All** 只评判页面完整呈现过的图片和文档：只列了名字的、显示不全的、由 Quick Look 呈现的（PDF、网页）、呈现不出来的（比如注明无法显示的图片）都不算。每个视频和音频都要单独给出结论。每条命令都写明它作用于几件作品，菜单还会说明本页还有几个文件要逐个审阅，以及里面的合集要在各自的页面审阅。文件已不在磁盘上、但 Gleaner 存有它某一版的副本时，先给出 **Show Saved Version**，再给出 Remove from Collection。每件作品带四个各自独立的状态：它怎么来的（回复点名、随文件夹交付，或你保留的）、是否在这台 Mac 上、你的审阅结论，以及你是否标记为已发布。**Review** 可以通过、要求修改或拒绝，并附一句说明；**Mark Published…** 记下发布在哪里。结论只对你作出它时 Gleaner 哈希过的那份字节有效：文件变了，结论留在历史里，作品会先说它可能已变，读过之后再说已变。**To Review** 列出还剩下什么：合集里还没有针对当前字节作出结论的作品，以及结论针对的是别的字节的作品。

结论所针对的字节，Gleaner 手里没有副本时（超过 64 MB 的文件，或没能存下的文件），会如实标出：*Not kept*，附上大小；在文件仍是那份字节时，还会说明 Git 是否忽略这个文件、它是未提交还是已提交。你要求保存却没能存下的副本，会说明原因。旁边的 **Save a Copy** 能在文件仍是那份字节时存下它们；填写说明的表单里也有这个选项，选要求修改时默认勾上，因为修改会直接覆盖这个文件。存下之后，这份字节可以和磁盘上的文件对比，也能像任何版本一样拖出去。

会话工作期间出现或改动、但没有任何回复交付的文件，按会话列在项目概览末尾的 **Observed** 下；隐藏文件（如 `.env`）从不列入。**Keep** 按你看到的样子把它收进资料库；**Add to Collection** 把它收进某个合集；**Not From This Session** 把它从这个会话名下移开。

## 状态

Gleaner 只陈述自己核查过的事：文件在不在、能不能读、哈希、git 状态。回复里的说法，如“测试通过”“最终版”，作为 agent 的原话引用，不会变成状态。文件在那里却读不了，绝不会被说成不在、改过或读到过。

**Gleaner 第一次怎样读到每次交付**，见 Versions（用标记表示，例外用文字说明）和 More Info：

| 状态 | 含义 |
|---|---|
| Seen at delivery (filled dot) | 回复后十分钟内读到文件，且此后文件未被修改 |
| First seen later (hollow dot) | 交付之后才第一次读到，例如补读旧日志时；可能与交付时不同。凡是标出这次交付编号的地方，都带着“first seen later” |
| Never seen | Gleaner 第一次查看时，这个路径上什么都没有 |
| Never read | Gleaner 第一次查看时路径上有东西，却读不了：打不开的文件（例如没有权限），或者不是普通文件（管道、套接字或设备） |
| Listed, not read | 随回复所交付的文件夹一起交付的文件，只按大小和日期列出；你选中、打开、比较或拖动它时，Gleaner 才读它 |

Gleaner 没见过或没读到的交付，会在 Gleaner 第一次读到该文件时补记为 *first seen later*，只补一次。随文件夹列出的文件也在那时读取，前提是它仍与列出时一致：回复后十分钟内读到且此后没有改动，记为 *seen at delivery*，否则记为 *first seen later*。读到过的字节不会再被改写。

**On Disk**（磁盘上的现状），见 Information，选中文件时核查：

| 状态 | 含义 |
|---|---|
| Same as delivery N | 磁盘上的文件与第 N 次交付哈希一致 |
| As first seen | 文件与最新一次交付一致，但那次交付的字节是交付之后才第一次读到的 |
| Changed | 路径上现在的东西（一个文件，或者原本交付文件的地方换成了文件夹）与任何一次交付都不一致 |
| Back to delivery N | 磁盘上的文件回到了较早的第 N 次交付，而不是最新一次 |
| Back to delivery N as first seen | 磁盘上的文件与较早的第 N 次交付一致，但那次的字节是交付之后才第一次读到的 |
| Can't verify | 路径上有文件，但 Gleaner 从未读到最新一次交付，无法判断是不是它 |
| Folder | 交付的文件夹，显示它现在的样子；文件夹不分版本 |
| Not a file | 管道、套接字或设备；Gleaner 不会打开它 |
| Can't read | 路径上有东西，但 Gleaner 打不开或读不了，无法判断是哪一版 |
| Not on disk | 文件已不在磁盘上；有存档副本时提供副本，git 历史里该路径还有文件时注明 |
| Lost | 文件不在，没有存档副本，git 里这个路径也查不到；交付记录保留 |

**转交**（Hand-off），见文件名下方，针对你选的那次交付：

| 状态 | 含义 |
|---|---|
| Verified · file on disk | 磁盘上的文件与这次交付哈希一致；拖出的是 Gleaner 复制后核对过的副本 |
| Verified · saved copy | 磁盘上的文件已不是这次交付；拖出的是 Gleaner 的存档副本，按哈希核对过 |
| First seen later | 这些字节是交付之后才第一次读到的，可能与交付时不同 |
| Delivery N is no longer available | 磁盘上的文件和存档副本现在都没有这次交付的字节，或交付的文件夹已不再是文件夹。Gleaner 说明为什么没有副本；改为显示磁盘上的当前文件：它是另一次交付时注明那一次，否则标注“not a found delivery” |
| Delivery N isn't available | Gleaner 从没见过或没读到这次交付的字节 |
| Delivery N isn't available now | 路径上有东西，但 Gleaner 读不了 |
| Restore from git first | 文件已不在，git 历史里这个路径还有文件；Gleaner 给出一条由你执行的命令 |
| Delivery N is lost | 文件已不在，没有存档副本，git 里这个路径也查不到；交付记录保留 |
| Folder | 交付的文件夹，按它现在的样子交出 |

**副本**（Copy），见 More Info，说明这次交付的字节存在哪里：

| 状态 | 含义 |
|---|---|
| Saved copy | Gleaner 存有这次交付的字节 |
| Saved copy of what Gleaner first saw | Gleaner 存有它在交付之后第一次读到的字节 |
| Not saved: too large | 超过 64 MB，且没有用 Save a Copy 存档 |
| Not saved: saving failed | Gleaner 读到了文件，但没能存下副本 |
| Saved copy gone from Gleaner's store | Gleaner 存过副本，但它的存储里已经没有了 |
| Not saved: never read | Gleaner 从没见过或没读到这次交付的字节 |
| Folder: not versioned | 交付的文件夹；Gleaner 不存副本 |

没有存档副本的三种情况，后面接着最近一次核查的结果：磁盘上的文件仍是它（按哈希核对）、不在磁盘上、磁盘上的文件读不了，或磁盘上的文件已不是它。

**列表中**，每行最多一个标记，只在需要留意时出现：*Unavailable* 并说明原因（never seen、never read、not on disk、can't read、not a file、a folder now、changed），*Not on disk*，*Changed*，或 *First seen later*。绘制列表时从不读取磁盘，所以只有在应用打开后核查过的文件才会标 *Changed*。交付过不止一次的作品在第一行末尾标出交付次数；只有显示的不是最新一次时，才写“Delivery N of M”。展开的作品下，某次交付无法交出时，那一行标 *Unavailable* 并说明原因。

**每个 agent** 都有一个开关，在 Sources（⌘,）和工具栏的 Sources 弹窗里。关掉后，Gleaner 不再读取或监视它的日志，并隐藏它的交付；不会删除任何内容，重新打开即全部恢复。agent 的页面画出它通往服务商和回复所用模型的连线，每个模型带着厂商的标志；交付的 Information 也写明所用模型。

**agent 日志**，见 Sources（⌘,）、Sources 行末的三角标记，需要留意时也会在列表下方用一行显示：*Read*；*Read with problems*（有未知的记录类型或字段；有格式错误的行或比之前更短的日志；没有最终回复的日志，仍在进行的最后一轮和你中断的一轮不算；已结束的轮次中回复比之前少的日志；读不了的日志或文件夹；没能走完的工作区）；*Can't read*；*Not on this Mac*。agent 的页面逐一列出每个问题背后的日志和未知名称。重读可能有用时会出现 Try Again，已经找到的内容照常显示。

## 转交

把详情栏顶部的文件，或列表中的一行，拖进 Finder、聊天窗口或上传框。列表中的一行交出的版本与详情栏一致：选中的文件交出你选的那次交付，其他行交出匹配到的那次。对方拿到的是一份副本：Gleaner 复制后重新计算哈希，与所选版本一致才交出，原文件不会被移动，核对之后的改动也混不进来。磁盘上的文件已经变了，就交出存档副本。交付的文件夹按它现在的样子以副本交出，而且只在它仍是文件夹时。

文件和存档副本都没有这一版时，Gleaner 会说明为什么手里没有它的字节：从没见过或没读到，那次交付的是文件夹，文件太大没有存档，存档失败，或者存过的副本已不在它的存储里。只要读得了路径上的文件，就改为显示它，可读可审：它是另一次交付时注明那一次，否则标注“not a found delivery”。无可交出的行拖不起来。文件已不在、但 git 里还有时，Gleaner 给出一条由你执行的命令，指明一个核实过包含该文件的提交：从那个提交 `git restore`，或者对已删除的 worktree，在那个提交上 `git worktree add`。Gleaner 自己从不执行。凡是 Gleaner 建议再查一次的地方，**Check Again** 都会当场核查文件并重新准备副本。

| 操作 | 快捷键 |
|---|---|
| 复制核验过的文件（焦点在列表时） | ⌘C |
| 打开核验过的文件 | ⌘O |
| Quick Look | 空格或 ⌘Y |
| 在 Finder 中显示原文件（Show in Finder） | ⇧⌘R |
| 拷贝原文件路径（Copy Path） | ⌥⌘C |
| 拷贝交付的引用（Copy Reference） | ⇧⌘C |
| 检查新交付 | ⌘R |
| 撤销一次 Join、Keep Apart 或移动 | ⌘Z |
| 关闭对比 | Esc |

Show in Finder 和 Copy Path 针对原文件所在位置，那里的文件可能在交付后改过。文件已不在时，Show Folder 打开它原来所在的文件夹；那个文件夹也不在了，就如实说明。复制、打开、Quick Look 和拖拽用的都是核验过的副本。

## gleaner 命令

`gleaner` 让 Mac 上的编码 agent（Claude Code、Codex）自己找到你说的那个文件，选定确切的版本，只读需要的部分，再把这些字节交出去，不必自己翻日志。它从源码构建，与应用放在一起：`swift build -c release --product gleaner` 会生成 `.build/release/gleaner`。发布包里只有应用。agent 按 `gleaner` 这个名字运行它，所以要把它链接到 PATH 上的某个文件夹，例如 `/usr/local/bin`，macOS 会把它放进每个 shell 的 PATH（文件夹不归你所有时加 `sudo`）；每次重新构建后，链接指向的就是新版本：

```bash
ln -s "$PWD/.build/release/gleaner" /usr/local/bin/gleaner
```

| 命令 | 回答 |
|---|---|
| `gleaner find <terms…> [--project P] [--kind K] [--limit N]` | 所有词都匹配的文件，从新到旧，各按匹配到的那次交付列出，并附总数 |
| `gleaner show <delivery>` | 这次交付及其文件的每次交付、磁盘上的现状、转交时会交出什么，以及交付它的那次要求和回复 |
| `gleaner read <delivery> [--lines A:B \| --bytes A:B] [--max N]` | 这一版原样字节的文本，不另行指定时最多 16 KB；绝不拿当前文件的字节顶替 |
| `gleaner outline <delivery> [terms…] [--limit N]` | 这一版原样字节里的标题，各带其小节的字节和行范围，只读报告里的某一条发现；`R1` 绝不会找到 `R10`，两个都匹配的标题会一并列出 |
| `gleaner resolve <delivery>` | 它的引用：资料库、交付的 id、哈希和路径、提到它的日志行、Gleaner 第一次怎样读到它，以及它的字节现在在哪里 |
| `gleaner handoff <delivery>` | Gleaner 缓存里这一版的一份只读副本的路径，已按哈希核对 |
| `gleaner verify <delivery or reference file>` | 原文件、Gleaner 的存档副本，是两者都有、只有其一，还是都没有引用里的字节 |

每条命令向 stdout 写一个 JSON 对象，失败时也一样，写成 `{"error": {"kind": …, "message": …}}`，消息同时写到 stderr。退出码：0 成功；1 找不到、这一版没有字节，或其他失败；2 用法错误；3 没有资料库，或资料库属于另一个版本（打开 Gleaner 即可创建或更新）。`--home <folder>` 读取为另一个主文件夹保存的资料库，与应用的 `-GleanerHome` 相同。

命令从不建索引，以只读方式打开资料库：它按应用最近一次读到的内容回答。每个回答，以及资料库打开之后的每次失败，都带着这份 `index`（资料库、运行过几次、最近一次何时结束、各 agent 的日志读得怎样，或已关闭），所以过时或不完整的索引给出的空结果，不会被当成什么都没交付的证据。打开 Gleaner 就能更新它。它按应用呈现的样子回答：在 Sources 里关掉的 agent 在这份索引里记为 `off`，它的交付不在回答里；每个文件归在应用显示它的那个项目里，你做过的更正都算数。命令从不写入资料库或项目文件夹；`handoff` 只写它的副本，放在 Gleaner 的缓存里。

**给 agent 的宿主用。** `gleaner mcp` 通过 stdio，把同样的七个调用作为 MCP 工具提供：`gleaner_find`、`gleaner_show`、`gleaner_read`、`gleaner_outline`、`gleaner_resolve`、`gleaner_handoff` 和 `gleaner_verify`。参数与命令同名（`lines` 和 `bytes` 写成 `"A:B"`；命令接收引用文件的地方，`gleaner_verify` 接收交付的 id，或以对象形式给出的引用），回答是同样的 JSON，既作为结构化内容，也作为文本。失败时是一个工具错误，带着同样的 `{"error", "index"}` 对象。服务端不保留状态：每次调用都以只读方式打开资料库，stdout 上只写协议消息。Gleaner 从不自行注册到任何宿主。要把它加到 Claude Code，范围由你选定（默认是 local；`--scope user` 用于你的所有项目，`--scope project` 通过项目的 `.mcp.json` 共享）：

```bash
claude mcp add gleaner -- <path to gleaner> mcp
```

要把它加到 DeepSeek Harness，就为它的 MCP 客户端插入一行，写在 `$DSH_HOME/cordis.patch.yml` 里（与其中已有的内容合并），或写在一个用 `--patch` 传入的文件里：

```yaml
- insert:
    - id: mcp-gleaner
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: gleaner
        transport: stdio
        command: <path to gleaner>
        args: [mcp]
```

`<path to gleaner>` 是你构建好的命令，例如 `.build/release/gleaner` 的完整路径。在 `mcp` 后加 `--home <folder>`，就为另一个主文件夹保存的资料库提供服务。

**作为 skill 使用。** `extensions/gleaner` 是一个 [Agent Skills](https://agentskills.io) 文件夹，告诉 agent 何时、怎样使用 Gleaner：凭你自己的描述，找到 agent 早先交付的文件；用它的 `gleaner://delivery/<id>` 链接在 Gleaner 里打开；用 `handoff` 或 `read` 交出它确切的那一版，给你转交副本的路径或引用，而不是把文件内容贴出来。它只运行 `gleaner` 命令，以及打开 `gleaner://` 链接的 `open`，自己什么也不保存。Claude Code、Codex 和 DeepSeek Harness 读的是同一个文件夹。Gleaner 从不自行安装它：在仓库里运行下面的命令，把它链接（或拷贝）到各自读取 skill 的位置：

```bash
mkdir -p ~/.claude/skills ~/.agents/skills
ln -s "$PWD/extensions/gleaner" ~/.claude/skills/gleaner   # Claude Code
ln -s "$PWD/extensions/gleaner" ~/.agents/skills/gleaner   # Codex 和 DeepSeek Harness
```

放在项目自己的 `.claude/skills` 或 `.agents/skills` 文件夹里也可以。skill 默认 `gleaner` 在 PATH 上，否则由你告诉 agent 它在哪里。

在应用里，**Copy Reference**（⇧⌘C，位于 Edit 菜单、详情栏的 ⋯ 菜单，以及列表行和版本行的右键菜单）把一次交付的引用按 `gleaner resolve` 给出的样子拷贝下来，可以贴给 agent。**Show in Log**（位于 File 菜单、⋯ 菜单和同样的右键菜单）在 Finder 中选中会话日志；More Info 给出提到这个文件的那条回复所在的行；agent 已删掉日志时则说明这一点。显示日志并不是恢复对话：恢复对话用 Copy Resume Command。`gleaner://delivery/<id>` 链接会打开 Gleaner 并定位到那次交付；链接指向的交付不在这个资料库里，或它的 agent 在 Sources 里已关闭时，如实说明。

## 交付的认定

Gleaner 只读每一轮的最终回复，回复把文件交到你手上，才收录：

- 指向本地文件的 Markdown 链接或图片，收录；标题锚点（`[guide](docs/guide.md#usage)`）不影响收录。
- 行内代码或裸路径，要带文件夹、且不带任何锚点才收录，例如 `out/report.html`；只有文件名（`App.tsx`）不收。
- 带行号锚点（`main.swift:42`、`#L42`）的是代码引用，即使写成链接也一律不收。
- 围栏代码块里的路径（没有闭合的围栏一直延续到回复末尾）、写在行内代码里的链接、带占位符的路径（`build/<name>.zip`）属于示例，不算交付。

子 agent 的回复不是给你的，跳过。这条规则从“交付”的定义推出，没有在大量真实日志上测量过；漏收或误收的例子有助于调整它。

## 读取与保存

- **读取** `~/.claude/projects` 下的 Claude Code 日志、`~/.codex` 下的 Codex 日志，以及回复里提到的文件。应用开着时监视日志文件夹，启动后才出现的也一样。通过读取 `.git` 条目找到文件所属的仓库，在仓库里只运行只读的 git 命令：文件在磁盘上时运行 `git status --porcelain --ignored`；文件已不在时运行 `git rev-parse` 和 `git log --all`，找出包含它的提交。每条命令都带 `--no-optional-locks`，git 不会改写索引；也不会运行仓库配置的任何东西：关闭 `core.fsmonitor`，不启动钩子或守护进程；关闭签名校验，`git log` 不启动签名程序；在部分克隆（partial clone）里，不去拉取克隆缺少的内容。git 比较文件时，clean filter（例如 Git LFS）仍可能运行。
- **观察**每个会话工作的文件夹（它所在的 git 检出，否则就是该文件夹本身），在读过它的日志、会话的时间段有变化之后走一遍：创建或修改日期落在会话工作期间（从每个请求到回答它的最后一次回复）的文件，只记名称、大小、日期和文件标识，从不读内容。日期是在那之后才设上的文件（比如保留了旧日期的副本）不算。这样的文件是在那次会话期间*出现*或*改动*的，并不说明是谁做的；它与交付并列保存，从不算作交付。包（应用、Xcode 项目）按它自己的日期算作一个条目。主目录及其 Library（iCloud Drive 和云存储除外）、系统文件夹、隐藏文件和隐藏文件夹、agent 的日志、Gleaner 自己的资料库、依赖缓存（`node_modules`、`__pycache__`、`DerivedData`）以及工具用 `CACHEDIR.TAG` 标为缓存的文件夹都跳过，没走的工作区及原因 Sources 会列出；不跟随链接，不进入别的卷，一次最多走 100,000 个条目，超出时 Sources 会报告。详见 [docs/design/capture.md](docs/design/capture.md)。
- **列出**回复所交付文件夹里的文件，作为随它交付的文件：只记名称、大小、日期和文件标识，从不读内容，也从不列隐藏文件，跳过的内容和条目上限与走工作区时相同。创建日期和最后一次 inode 变动都不晚于回复的文件才算，此后改动、移入或复制进来的文件宁可漏掉，也不冒认；每个文件的字节在你选中、打开、比较或拖动它时才读取。文件夹里的 Git 仓库属于另一个项目，不列入，并在文件夹的详情里写明；包（应用、Xcode 项目、RTFD 文档）按 Finder 的显示算作一个文件。主目录、卷或云盘、它们下面直接的文件夹、链接、隐藏文件夹或缓存里的文件夹、包、项目自己的文件夹或包含它的文件夹都不展开，文件夹的详情和 Sources 会说明原因。详见 [SPEC §5.4](docs/SPEC.md)。
- **保存你的审阅**：你建的合集（collection）、你从会话观察到的文件里保留下来的文件，以及你的审阅结论和发布标记。每一条都绑定在你作出它时 Gleaner 哈希过的那份字节上，并记下文件的大小和日期。文件变了，原来的结论留在历史里，并标明文件已变，从不沿用到新的字节上。详见 [SPEC §5.5](docs/SPEC.md) 和 [docs/design/review.md](docs/design/review.md)。
- **保存**回复和要求的摘录，不存完整日志。摘录截短之前，先抹去形似密钥的字符串：API key 和访问令牌、bearer token、`key=value` 形式的密钥、URL 里的凭据，以及 40 个以上字母和数字组成、大小写字母和数字混杂的串。小写十六进制串（哈希、ID）保留。索引和存档副本放在 `~/Library/Application Support/Gleaner`。64 MB 以内的文件，第一次读到时就存一份；更大的文件只记哈希，磁盘上的文件仍与交付一致时，可以用 **Save a Copy** 存下；审阅结论所针对的字节，也可以在它的那一行这样存下。存档副本是交付时的原样字节，不做抹除。
- **转交副本**放在 `~/Library/Caches/Gleaner`。Sources → Storage 里能看到占用并清除；清除时保留剪贴板上的那份（粘贴时还要读它），也不会动存档副本。
- **不写入**项目文件夹。Gleaner 自身不发网络请求；用 Quick Look 预览网页时，页面可能加载它引用的资源，链接只在你点击时打开。

## v0.1 的限制

- 文件夹只列出、不分版本：预览、打开和拖拽用的都是它现在的样子。所交付文件夹里的文件则逐个分版本。网页引用的图片、脚本和样式表不随页面保存，Quick Look 预览网页时也不带它们。
- 超过 64 MB 的文件，只有在磁盘上的文件仍是那份字节时，在某个版本或某条审阅结论上选 **Save a Copy**，才会存下。没存下的大文件所在的 worktree 一旦删除，Gleaner 只能通过 git 提供它（给出一条由你执行的命令），而且前提是文件提交过；否则就丢失了。可能还要用的大文件，删除 worktree 之前先存一份。
- git 比较文件时，clean filter（例如 Git LFS）仍可能运行。
- 给自建项目改名不算更正：撤销不会还原，Corrections 里也不列出。要改回去，再改一次名。
- 交付认定规则是暂定的，有待更多用户日志的反馈。
- 会话期间观察到的文件列在项目的 Observed 下，但只限有回复交付过东西的项目。时间段止于最后一次回复，所以最终回复之后的工作、被打断的一轮、以及在回答它的最后一次回复之后仍在运行的后台任务都不在其内。时间段之后被改名或改了权限的文件，和保留旧日期的副本一样不算。
- Gleaner 对审阅过的文件看到了什么，只在它运行期间记得：看到文件变了、随后文件被删，在退出之前一直说已变；重新启动后，结论按作出时的样子保留。
- 应用还没有图标，发布包只做了临时签名（ad-hoc），没有公证。

## 开发

```bash
swift test                      # fixture 测试
./scripts/bundle-app.sh         # 生成 build/Gleaner.app，临时签名
./scripts/release.sh            # 先跑测试，再生成 build/Gleaner-<版本>.zip 及其 sha256
```

工作区有未提交的改动时，`release.sh` 不会运行。打了 `v0.1.0` 标签的提交构建为 0.1.0 版，其他提交构建为 `0.1.0-dev+<commit>`。

- `Sources/GleanerCore`：各 agent 的日志适配器（Claude Code、Codex）、提及抽取、文件定位、脱敏、索引库（SQLite）、内容库（存档副本与核验过的转交副本）、索引器、对每个会话工作区的观察（`Observations.swift`）、所交付文件夹里的文件（`Bundles.swift`）、这些列表的排序（`Listing.swift`）、合集、保留的文件与审阅（`WorkUnits.swift`、`Keeping.swift`、`Review.swift`）、日志监视，以及状态判断（`Library.swift`）。
- `Sources/GleanerUI`：窗口所用的组件库：标记、状态、表面、控件与动效，依 [docs/design/components.md](docs/design/components.md)。只依赖 SwiftUI 与 AppKit。
- `Sources/Gleaner`：macOS 应用（SwiftUI、AppKit、Quick Look、AVKit）。
- `Sources/gleaner-cli`：`gleaner` 命令，以 JSON 给出 catalog 的回答；以及 `gleaner mcp`，把同样的回答作为 MCP 工具提供。
- `Sources/gleaner-spike`：Spike A，只读地抽取本地日志，输出一份标注表。
- `Sources/gleaner-index`：开发工具，不开窗口就为一个合成的 home 建一次索引，供 `gleaner` 读取。不随发布包提供。
- `extensions/gleaner`：Claude Code、Codex 和 DeepSeek Harness 读取的 skill。
- `Tests/GleanerCoreTests`：用脱敏后的日志记录结构写成的 fixture 测试，整个流程的测试（并发编辑、删除 worktree、回滚、补读旧日志、核验后转交），几类工作中的观察和所交付的文件夹，合集、保留的文件和绑定在字节上的审阅结论，以及 catalog 的查询。
- `Tests/GleanerUITests`：标记、设计令牌，以及画出每个组件的图库（`GLEANER_GALLERY=<文件夹> swift test --filter GalleryTests`）。
- `Tests/GleanerTests`：在合成的资料库上检验应用的判断（点一下落在哪次交付上，Quick Look、Compare 和拖拽用的是哪份字节）及其措辞。
- `Tests/GleanerCommandTests`：像 agent 的 shell 那样运行构建好的 `gleaner`：检验它的 JSON、退出码，以及它既不写资料库也不写项目；再像宿主那样运行 `gleaner mcp`，把每个工具的回答和拒绝与命令自己的对照；拿构建好的命令核对 skill 里给出的每条命令；以及 `gleaner-index`，检验它建出的资料库与应用的索引器建出的一致。

v0.1 的设计决定见 [docs/SPEC.md](docs/SPEC.md)，设计探索与裁决见 [docs/design/](docs/design/README.md)。

### 不开窗口为合成的 home 建索引

```bash
scripts/acceptance-home.py /tmp/gleaner-home initial
swift run gleaner-index --home /tmp/gleaner-home
.build/debug/gleaner find guide --home /tmp/gleaner-home
```

`gleaner-index` 像应用带 `-GleanerHome` 启动时那样为这个 home 建一次索引，并以 JSON 输出资料库的 index，以及这次读了什么、新增了什么；`--now <ISO 8601>` 固定这次运行的时钟。它必须给出 `--home`，拒绝你自己的 home 文件夹和更新版 Gleaner 打开过的资料库，也从不打包进应用（[docs/design/headless-indexing.md](docs/design/headless-indexing.md)）。

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
