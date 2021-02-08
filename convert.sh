#!/bin/sh

fn="$(ls _posts/*$1* | head -n1)"

if [ "$fn." = "." ]; then
    echo "Usage: $0 <fn_pattern>"
    exit 1
fi



for platform in wechat simple; do
    md2zhihu \
        -r git@gitee.com:drdrxp/bed.git@openacid \
        -p $platform \
        --keep-meta \
        --code-width 600 \
        $fn \
        -o ${fn%.md}-$platform.md
done
