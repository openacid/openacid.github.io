#!/bin/sh

# fn="$(ls _posts/*$1* | head -n1)"

# if [ "$fn." = "." ]; then
#     echo "Usage: $0 <fn_pattern>"
#     exit 1
# fi



# for platform in wechat simple; do
#     md2zhihu \
#         -r git@gitee.com:drdrxp/bed.git@openacid \
#         -p $platform \
#         --keep-meta \
#         --code-width 600 \
#         $fn \
#         -o ${fn%.md}-$platform.md

# done


# === Build for copying to other platform only ===
#
# The assets do not need to be kept after publishing on other platforms.

fn=_src/abstract-paxos/2022-03-27-abstract-paxos.md
name=${fn##*/}

# Build zhihu specific md
#
# Usage: import md to zhihu

platform=zhihu
md2zhihu \
    --platform         $platform \
    --code-width       600 \
    --refs             _data/refs.yml \
    --output-dir       ./md2-$platform \
    --asset-output-dir ./md2-$platform/ \
    --md-output        ./md2-$platform/ \
    --repo             git@gitee.com:drdrxp/bed.git@openacid-$platform-import-assets \
    $fn


# Build wechat specific html.
# Render it to the last article.
# 
# Usage: push and let github build it and copy the html on a browser.

platform=wechat
md2zhihu \
    --platform         $platform \
    --code-width       600 \
    --refs             _data/refs.yml \
    --keep-meta \
    --output-dir       ./md2-$platform \
    --asset-output-dir ./md2-$platform/ \
    --md-output        ./_posts/2000-01-01-wechat-import.md \
    --repo             git@gitee.com:drdrxp/bed.git@openacid-$platform-import-assets \
    $fn

