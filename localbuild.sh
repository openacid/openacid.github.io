#!/bin/sh

# build and output to local repo

find _src -name "*.md" \
    | while read fn; do
    name=${fn##*/}

    platform=wechat
    md2zhihu \
        --platform         $platform \
        --code-width       600 \
        --refs             _data/refs.yml \
        --keep-meta \
        --output-dir       . \
        --asset-output-dir ./md2/$platform \
        --md-output        ./md2/$platform/ \
        --repo             .@try-md2$platform \
        $fn

done

