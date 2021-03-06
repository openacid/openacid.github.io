
习惯了用markdown做各种笔记或创作, 想要分享到知乎的时候,
发现知乎对文章导入markdown的支持并不很好, 不支持表格, 需要公开可访问的url的图片,
以及知乎私有的公式编辑功能.

于是有了这样一个工具 [md2zhihu](https://github.com/drmingdrmer/md2zhihu/) , 将markdown文档直接转换成可以导入到知乎的格式.
主要做3项转换: 公式, 表格和图片.

例如以下 markdown 源码:

```markdown
| Data size | Data Set                | gzip size | slimarry size | avg size   | ratio |
| --:       | :--                     | --:       | :--           | --:        | --:   |
| 1,000     | rand u32: [0, 1000]     | x         | 824 byte      | 6 bit/elt  | 18%   |
| 1,000,000 | rand u32: [0, 1000,000] | x         | 702 KB        | 5 bit/elt  | 15%   |
| 1,000,000 | IPv4 DB                 | 2 MB      | 2 MB          | 16 bit/elt | 50%   |
| 600       | [slim][] star count     | 602 byte  | 832 byte      | 10 bit/elt | 26%   |

$$
||X{\vec {\beta }}-Y||^{2}
$$

![](/post-res/md2zhihu/boo.jpg)
```

服用前的导入效果是这样:

![](https://cdn.jsdelivr.net/gh/openacid/openacid.github.io@_md2zhihu_b935d2/zhihu/md2zhihu/before.png)

服用后导入效果是...爽爽爽:

![](https://cdn.jsdelivr.net/gh/openacid/openacid.github.io@_md2zhihu_b935d2/zhihu/md2zhihu/after.png)

还等什么? 用起来!!!:

## Install

```sh
pip install md2zhihu
```

## Usage

```sh
md2zhihu your_great_work.md
```

这个命令将markdown 转换成 知乎 文章编辑器可直接导入的格式, 存储到默认目录 `_md2`:  `_md2/your_great_work/your_great_work.md`, 例如用本文做例子, 将输出以下转换/上传的步骤:

![](https://cdn.jsdelivr.net/gh/openacid/openacid.github.io@_md2zhihu_b935d2/zhihu/md2zhihu/runit.png)

然后通过知乎编辑器导入这个文档就可以啦.

`-o` 选项可以用来调整输出目录, 例如:

```
md2zhihu your_great_work.md -o my_zhihu_works/
```

## Features

-   公式转换:

    例如

    ```
    $$
    ||X{\vec {\beta }}-Y||^{2}
    $$
    ```

    <img src="https://www.zhihu.com/equation?tex=%7C%7CX%7B%5Cvec%20%7B%5Cbeta%20%7D%7D-Y%7C%7C%5E%7B2%7D%5C%5C" alt="||X{\vec {\beta }}-Y||^{2}\\" class="ee_img tr_noresize" eeimg="1">

    转换成可以直接被知乎使用的tex渲染引擎的引用:

    ```
    <img src="https://www.zhihu.com/equation?tex=||X{\vec {\beta }}-Y||^{2}\\" alt="||X{\vec {\beta }}-Y||^{2}\\" class="ee_img tr_noresize" eeimg="1">
    ```

-   自动识别block的公式和inline的公式.

-   表格: 将markdown表格转换成html 以便支持知乎直接导入.

-   图片: md2zhihu 将图片上传到github, 并将markdown中的图片引用做替换.

    -   默认命令例如`md2zhihu your_great_work.md`要求当前工作目录是一个git(作者假设用户用git来保存自己的工作), md2zhihu将建立一个随机分支来保存所有图片.

    -   也可以使用指定的git repo来保存图片, 例如使用`github.com/openacid/openacid.github.io` 这个repo来保存图片, 要求是对这个repo有push权限:

        ```
        md2zhihu your_great_work.md -r https://github.com/openacid/openacid.github.io.git
        ```

## Limitation

-   知乎的表格不支持table cell 中的markdown格式, 例如表格中的超链接, 无法渲染, 会被知乎转成纯文本.
-   md2zhihu 无法处理jekyll/github page的功能标签例如
    ```
    { % octicon mark-github height:24 % }
    ```

    将会做为纯文本被处理. 这部分文本目前需要导入后手动删除或修改.

## 改进

有什么需求, 进来聊聊吧: [在 github discussion 撩我](https://github.com/drmingdrmer/md2zhihu/discussions/new)

{% include build_ref %}


[md2zhihu]: https://github.com/drmingdrmer/md2zhihu/