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

find _src -name "*.md" \
    | while read fn; do
    name=${fn##*/}

    platform=wechat
    md2zhihu \
        --platform         $platform \
        --code-width       600 \
        --refs             _data/refs.yml \
        --keep-meta \
        --output-dir       ./md2 \
        --asset-output-dir ./md2/$platform \
        --md-output        ./_posts/$name-$platform.md \
        --repo             git@gitee.com:drdrxp/bed.git@openacid-md2$platform \
        $fn

    platform=zhihu
    md2zhihu \
        --platform         $platform \
        --code-width       600 \
        --refs             _data/refs.yml \
        --output-dir       ./md2 \
        --asset-output-dir ./md2/$platform \
        --md-output        ./md2/$platform/ \
        --repo             git@gitee.com:drdrxp/bed.git@openacid-md2$platform \
        $fn
done

