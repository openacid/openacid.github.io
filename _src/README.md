将当前目录下的一个文章 build 到 jekyll 的 `_post` 目录下:

in this dir:

```
./build.sh crc/2025-08-27-crc.md
```


publish to wechat platform:

```
# in the repo root:
./build-platform-specific.sh
```

Above step: upload the images to R2 storage.

Open in browser the local file, copy paste in wechat article editor:

```
file:///Users/drdrxp/xp/vcs/github.com/openacid/openacid.github.io/md2-local/2026-05-11-raf-without-term-cn-wechat-remote.html
```

The images are on remote so that wechat editor is able to download them
automatically.
