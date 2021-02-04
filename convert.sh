#!/bin/sh

fn="$(ls _posts/*$1* | head -n1)"

if [ "$fn." = "." ]; then
    echo "Usage: $0 <fn_pattern>"
    exit 1
fi


md2zhihu -r git@gitee.com:drdrxp/bed.git@openacid $fn -p wechat --keep-meta --code-width 600 -o $fn-wechat.md
