# OpenACID blog

This repository builds https://blog.openacid.com with Hugo and local
templates. The old Jekyll site is preserved in tag `v1-jekyll`.

## Writing guidelines

以下规范适用于本仓库文章的起草、改写和翻译。

- 文章开篇先说明新功能、方案或观点带来什么价值，再用具体效果让读者感受其重要性。例如，先说明应用可以自定义 read quorum 和 write quorum，再说明 4 个 node 的集群采用 `write quorum = 2` 时，commit 可以少等 1 份日志复制确认。
- 整篇文章、每个章节和每段的开头，都先给出结论、目的或要解释的核心问题。标题和首段要让读者知道为什么需要这部分、后文要解释什么、最终能得到什么答案，以及它与前文的关系。
- 介绍具体类型或并列实现时，标题采用“名称：简短特性”，名称放在最前面。例如：“ThresholdMembership：按 node 数定义 quorum”。
- 展开顺序是“具体的目标或结论 → 实际对象、操作和例子 → 术语与规律”。先让读者看见谁做了什么，再归纳抽象概念。例如，先写“4 个 node、write quorum 为 2 时，node 1、2 各保存 `foo=1` 对应的 log entry，取得 2 份确认后即可 commit”，再说明“`{1,2}` 构成 write quorum”。
- 句子要有明确的主语、动作和对象，写清必要的前提，让读者用较少上下文就能理解。指代必须能在当前句或前一句中唯一确定；需要回头查找时，直接重述对象名称。
- 用尽可能少的文字和概念说明白要点，每句只表达 1 个意思。删除不影响理解的铺垫、重复解释和旁支推导。新术语只为文章主线服务，定义后保持名称一致。
- 语气严肃但轻松，友好、平实，直接陈述。用具体的技术收益和可核对的效果吸引读者。英文使用短句和常用词，技术术语保持准确。
- 数字随例子和方法出现，写清参数、比较基准、推导依据和适用条件。技术效果要说到实际改变的操作，例如“commit 少等 1 份日志复制确认”，并交代其他 node 仍会接收 append entries。
- 代码示例围绕当前要解释的问题展开，标注关键行并交代变量来源。node、地址、权重等在正文、代码和图中保持一致。需要展示树、网格或流程时，用简短的 ASCII 图；需要对照接口行为时，用表格。
- 示意图先确定当前章节要解释的对象和关系。有结构的 membership 用边界、位置、连线和分支表达 node 的组合与共享关系，并标清哪些 node 用于 election、哪些用于 append entries。membership change 的文字和图以 `C_old`、joint、`C_new` 为主体，只用 `.read`、`.write` 表示各自的 quorum 规则；joint 用 AND 分别组合旧、新的 read quorum 和 write quorum，连线标明同一 config 内及相邻 config 之间必须相交的 quorum。`ExplicitMembership` 用 quorum 列表定义 membership，图中直接列出所有 read quorum 和 write quorum。

### English terminology and numbers

文章面向有技术背景的读者。Raft 专有名词统一使用英文，覆盖标题、摘要、正文、表格、代码注释和插图。

| 统一写法 | 含义与用法 |
| --- | --- |
| `election` | Raft 选举。 |
| `quorum` | 使用专有名词，不以“确认条件”等普通词替代。数值语境可以直接用 quorum 表示大小，例如 `read quorum = 3`。 |
| `read quorum` | election 需要覆盖的 node 集合。 |
| `write quorum` | append entries 需要取得复制确认、以便 commit 的 node 集合。 |
| `vote request` | 投票请求消息。 |
| `request vote` | 请求投票的动作；具体 API 保留实际写法，例如 OpenRaft 的 `VoteRequest`、`vote()`。 |
| `append entries` | Raft 日志复制、追加动作；具体 API 保留实际写法，例如 `AppendEntriesRequest`、`append_entries()`。 |
| `commit` | Raft 日志提交。 |
| `node` | 节点；代码类型 `Node`、`NodeId`、`NodeInfo` 等保持原有大小写。 |

- `append entries` 描述日志复制，`commit` 描述日志提交，`client write` 描述应用写请求；按实际动作选词，保持各自含义清楚。
- 继续保留英文术语：`vote`、`leader`、`candidate`、`voter`、`learner`、`role`、`membership`、`membership change`、`config`、`joint`、`log entry`、`linearizable read`、`quorum set`、`barrier`。
- 实际数量和编号使用阿拉伯数字，包括 node 数、vote 数、副本数、quorum 数值、权重、维度和序号。例如：`4 个 node`、`3 个 vote`、`2 份副本`、`5 种实现`、`第 1 行`、`3×3`。
- 正常描述优先简写为 `read quorum = 3`、`write quorum = 2`，数值自然表示大小，省去 size。按权重计算时写清 read weight、write weight。代码中的 `write_size` 等标识符仍以实际 API 为准。

### Outlines and translation

- 提纲只列文章主线、主要章节和每节要点，保持简短。
- 英译时，每段英文紧跟对应中文；用户确认译文后再移除中文。翻译保留原文论证，用自然英文表达意思。

## Source and generated files

- `_src/<date>-<topic>/`: article Markdown and its images, diagrams, and
  attachments. English and Chinese versions can share a directory.
- `_src/refs.yml`: shared link definitions. Articles use `[text][key]`;
  `universal` applies everywhere, while `zhihu` and `wechat` override links
  for those platforms. Article front matter can define local `refs` and
  `platform_refs`. Quote YAML values containing `: `.
- `_src/Makefile`: compiles `images-typst/NN-name.typ` into
  `images/NN-name.png` with Typst, at 144 PPI.
- `_src/lib/typst/`: shared theme tokens and CeTZ drawing helpers. Article
  `images-typst/style.typ` files import this library; the Makefile sets `_src/`
  as Typst's project root and tracks the shared modules as build dependencies.
- `content/`: hand-written Hugo content, including the home page.
- `layouts/`: Hugo page templates, partials, and markup render hooks.
- `assets/css/main.css`: site styles.
- `static/`: files copied to the site without processing, including shared
  images, CSS for platform exports, and legacy resources.
- `data/authors.yaml`: author profiles referenced by article `authors`.
- `hugo.yaml`: routes, mounts, taxonomies, Atom feed, Markdown rendering,
  menus, and Giscus settings.
- `.build/`: generated Hugo input, one directory per article. Edit `_src/`
  rather than these files; `convert-posts.sh` deletes and rebuilds it.
- `public/`: generated website. It is ignored by the source repository and
  locally contains a separate Git repository for build comparisons.
  Preserve `public/.git` and keep its history separate from source commits.
- `md2-local/`: ignored output for exports to other publishing platforms.

## Build workflow

Run from the repository root:

```sh
./convert-posts.sh
hugo build
```

`convert-posts.sh` converts Markdown with the pinned Docker image
`ghcr.io/drmingdrmer/md2zhihu:v0.20`. It selects `_src/*/*.md` files whose
front matter contains `url:`, expands shared references, copies assets,
and renders supported diagram blocks. Its `--platform hugo` writes each
formula on one line, between the math delimiters that `hugo.yaml` sets.

Hugo mounts generated Markdown from `.build/` as `content/posts/` and its
assets as `/post-res/<article-name>/`. It writes the final site to `public/`.
Use `hugo server` for previews, or `hugo server --buildDrafts` to include
drafts. Rebuild `.build/` after changing article sources or references.
Run `make -C _src` when changing Typst figures; it requires Typst >= 0.14.

`snapshot-site.sh` runs both build stages, then stages and commits all changes
in the separate `public/` repository with `Build from <source HEAD>`.
Run it only when a generated-output commit is requested. For a comparison
without committing, run the two build commands above and inspect
`git -C public diff`. Historical comparisons use
`git -C public log --oneline` and `git -C public diff <before> <after>`.

`export-post.sh <platform> <source.md>` creates platform exports
in `md2-local/` and uploads them to R2. Run it only when an upload is intended.

## Editing and verification

Keep published `url` values and heading IDs stable: existing links and
Giscus discussions depend on them. Articles need `date` and `url` fields;
`draft: true` hides a page from production, but its assets are still copied.

Preserve the original `$` and `$$` math syntax in `_src/`; md2zhihu's
`hugo` platform converts it to Hugo's delimiters.

After link or rendering changes, compare generated HTML, not just source
Markdown. Check link destinations and labels, heading IDs, image paths,
and `feed.xml`. Shared reference titles also affect tooltips and the
generated `Reference:` lists, so those changes can be expected.

`.github/workflows/pages.yml` builds with Hugo 0.164.0 and deploys `public/`
to GitHub Pages on pushes to `main`. A push to `ci` runs only the build, to
test a commit before `main` receives it. Local build history is for debugging;
deployment uses the source repository's workflow.
