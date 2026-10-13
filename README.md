# OpenACID Blog（Hugo 版）

用 [Hugo](https://gohugo.io/) 生成 [blog.openacid.com](https://blog.openacid.com/)。不用第三方 theme，模板和 CSS 都在本仓库。

推送到 `main` 后，`.github/workflows/pages.yml` 构建网站，并发布到 GitHub Pages。为此，仓库设置中 Pages 的 Source 要选 GitHub Actions。原来的 Jekyll 站点保存在 tag `v1-jekyll`。

## 构建

依赖：

- [Docker](https://docs.docker.com/get-docker/)：`build-content.sh` 在镜像 `ghcr.io/drmingdrmer/md2zhihu:v0.19` 中运行 [md2zhihu](https://github.com/drmingdrmer/md2zhihu)。镜像里有 md2zhihu 用到的 graphviz、mermaid-cli 和 Chromium，所以本机不用安装它们。
- [Hugo](https://gohugo.io/installation/)，测试用的是 v0.164.0。

```bash
./build-content.sh   # 把 _src/ 中发布的文章转换到 .build/
hugo server          # 本地预览：http://localhost:1313/
hugo                 # 把整个网站生成到 public/
```

修改 `_src/` 中的原稿后，要重新运行 `./build-content.sh`。

## 构建流程

```text
_src/<YYYY-MM-DD-目录>/<名字>.md     原稿；front matter 有 permalink: 的才发布
  │  build-content.sh：md2zhihu 转换，再由 to-hugo.py 适配
  ▼
.build/<名字>/<名字>.md              每篇文章一个目录，放 Hugo 的文章输入
.build/<名字>/<图片和附件>            网址是 /post-res/<名字>/<文件>，与 Jekyll 站点相同
  │  hugo：hugo.yaml 把 .build/ 中的 .md 挂载到 content/posts/，其余文件挂载到 static/post-res/
  ▼
public/                           完整的静态网站
```

`.build/` 和 `public/` 都由构建生成，已写入 `.gitignore`，不提交。

md2zhihu 展开 `_src/refs.yml` 和原稿 `refs` 字段中的链接定义，复制图片和附件，并把图表代码块画成图片。

`to-hugo.py` 做三件事：

- 把 front matter 的 `permalink` 改名为 `url`，`excerpt` 改名为 `description`。
- 在 front matter 中写入 `date:`，值是原稿目录名的日期前缀。原稿自己写了 `date:` 时不改。
- 改写 `$$...$$` 公式。kramdown 把前后都是空行的 `$$...$$` 当作块公式，其余当作行内公式。Hugo 的 Markdown 解析器 Goldmark 不能这样区分，还会把引用块中跨行公式的 `>` 读进公式。所以 `to-hugo.py` 把每个公式合并成一行，并把块公式改写成 `\[...\]`。

## 文件

| 位置 | 内容 |
| --- | --- |
| `hugo.yaml` | 站点配置：URL、分类、feed、giscus 评论、Markdown 选项 |
| `layouts/` | 模板：`page.html` 是文章页，`home.html` 是首页，`home.atom.xml` 生成 `/feed.xml` |
| `layouts/_markup/render-passthrough.html` | 把公式输出成 MathJax 读取的 `\[...\]` 和 `\(...\)` |
| `assets/css/main.css` | 样式 |
| `data/authors.yaml` | 作者资料：名字、简介、头像、链接 |
| `static/assets/images/` | logo、favicon、作者头像、二维码 |
| `static/import-back/`、`static/py/`、`static/post-res/`、`static/assets/images/banner/` 等 | 旧站的 70 个文件，没有页面引用它们；放在这里，它们的旧网址才能继续访问 |
| `content/_index.md` | 首页；同时让旧网址 `/page2/` 跳转到首页 |
| `build-platform-specific.sh` | 生成文章的知乎版和微信版，并上传到 R2 |

## 原稿的 front matter

| 字段 | 作用 |
| --- | --- |
| `permalink` | 文章网址；没有这个字段的原稿不发布 |
| `title` | 标题 |
| `excerpt` | 摘要，用在首页列表、`<meta name="description">` 和 feed 中 |
| `authors` | `data/authors.yaml` 中的作者 id；id 不存在时构建失败 |
| `categories`、`tags` | 分类和标签，生成 `/categories/…` 和 `/tags/…` 页面 |
| `toc`、`toc_label` | 是否显示目录，以及目录的标题 |
| `mathjax` | 为 `true` 时加载 MathJax |

发布日期取自原稿目录名的 `YYYY-MM-DD-` 前缀。同一目录中日期不同的文章，用 front matter 的 `date:` 写明自己的日期，例如 `2025-10-02-raft-io-order/` 中的 `raft-io-order-fix.md`。

两条限制：

- 不要修改已发布文章的 `permalink`。giscus 按网址路径找 GitHub Discussions 中的讨论，路径一变，旧评论就对不上了。
- 列表项的第一行不能只有一个公式，例如 `- $$x$$`。kramdown 可能把它当作块公式，`to-hugo.py` 无法照做，遇到时报错退出。

## 没有迁移的内容

- GitHub Pages 把没有 front matter 的 Markdown 文件渲染成的 10 个网页：`/py/`、`/import-back/` 和 8 个 `/import-back/<目录>/<名字>/`。这些 Markdown 文件本身在 `static/` 中，例如 `/import-back/paxos/paxos.md` 仍可访问。
- 站内搜索。
- 文章的阅读时长，例如 "40 minute read"。
- Google Analytics `UA-69976993-2`：Universal Analytics 已于 2023-07-01 停止收集数据。
