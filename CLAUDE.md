# OpenACID blog

This repository builds https://blog.openacid.com with Hugo and local
templates. The old Jekyll site is preserved in tag `v1-jekyll`.

## Source and generated files

- `_src/<date>-<topic>/`: article Markdown and its images, diagrams, and
  attachments. English and Chinese versions can share a directory.
- `_src/refs.yml`: shared link definitions. Articles use `[text][key]`;
  `universal` applies everywhere, while `zhihu` and `wechat` override links
  for those platforms. Article front matter can define local `refs` and
  `platform_refs`. Quote YAML values containing `: `.
- `_src/Makefile`: compiles `images-typst/NN-name.typ` into
  `images/NN-name.png` with Typst, at 144 PPI.
- `content/`: hand-written Hugo content, including the home page.
- `layouts/`: Hugo page templates, partials, and markup render hooks.
- `assets/css/main.css`: site styles.
- `static/`: files copied to the site without processing, including shared
  images, CSS for platform exports, and legacy resources.
- `data/authors.yaml`: author profiles referenced by article `authors`.
- `hugo.yaml`: routes, mounts, taxonomies, Atom feed, Markdown rendering,
  menus, and Giscus settings.
- `.build/`: generated Hugo input, one directory per article. Edit `_src/`
  rather than these files; `build-content.sh` deletes and rebuilds it.
- `public/`: generated website. It is ignored by the source repository and
  locally contains a separate Git repository for build comparisons.
  Preserve `public/.git` and keep its history separate from source commits.
- `md2-local/`: ignored output for exports to other publishing platforms.

## Build workflow

Run from the repository root:

```sh
./build-content.sh
hugo build
```

`build-content.sh` converts Markdown with the pinned Docker image
`ghcr.io/drmingdrmer/md2zhihu:v0.20`. It selects `_src/*/*.md` files whose
front matter contains `url:`, expands shared references, copies assets,
and renders supported diagram blocks. Its `--platform hugo` writes each
formula on one line, between the math delimiters that `hugo.yaml` sets.

Hugo mounts generated Markdown from `.build/` as `content/posts/` and its
assets as `/post-res/<article-name>/`. It writes the final site to `public/`.
Use `hugo server` for previews, or `hugo server --buildDrafts` to include
drafts. Rebuild `.build/` after changing article sources or references.
Run `make -C _src` when changing Typst figures; it requires Typst >= 0.14.

`build-public.sh` runs both build stages, then stages and commits all changes
in the separate `public/` repository with `Build from <source HEAD>`.
Run it only when a generated-output commit is requested. For a comparison
without committing, run the two build commands above and inspect
`git -C public diff`. Historical comparisons use
`git -C public log --oneline` and `git -C public diff <before> <after>`.

`build-platform-specific.sh <platform> <source.md>` creates platform exports
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
