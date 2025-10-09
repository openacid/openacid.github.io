#!/bin/sh

# === Build for copying to other platform only ===
#
# It looks like gitee no longer support external access with refer
# --repo             git@gitee.com:drdrxp/bed.git@openacid-$platform-import-assets \

set -o errexit

# for example:
# https://pub-e254240c5c35410cb21a0cf4fb58f73e.r2.dev/2023-12-17-openraft-read.html
url_base="https://pub-e254240c5c35410cb21a0cf4fb58f73e.r2.dev"



# Call xp-md2html to convert md to html, using github-markdown.css
# xp-md2html is a personal repo
md2html()
{
    local src_path="$1"
    local output_path="$2"

    # TODO: add original link

    {
        cat <<-END
<!doctype html>
<html>
<head>
<meta charset='UTF-8'>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="github-markdown.css">
<style>
	.markdown-body {
		box-sizing: border-box;
		min-width: 200px;
		max-width: 980px;
		margin: 0 auto;
		padding: 45px;
	}

	@media (max-width: 767px) {
		.markdown-body {
			padding: 15px;
		}
	}
</style>
</head>
<body>
<article class="markdown-body">
END

        cat "$src_path" | xp-md2html

        cat <<-END
<img src="qrcode-hori.jpg" />
</article>
</body>
</html>
END

    } > "$output_path"
}


build()
{
    local platform="$1"
    local fn="$2"

    local name_suffix=${fn##*/}
    local name=${name_suffix%.md}
    # remove date
    local title=${name#20??-??-??-}

    echo ""
    echo "fn: $fn"
    echo "name: $name"
    echo "title: $title"
    echo ""

    # Build local markdown
    mkdir -p md2-local

    # reference local resource
    md2zhihu \
        --platform         $platform \
        --code-width       600 \
        --refs             _data/refs.yml \
        --output-dir       ./md2-local \
        --asset-output-dir ./md2-local/ \
        --md-output        ./md2-local/$name-$platform.md \
        $fn

    # reference remote resource
    md2zhihu \
        --platform         $platform \
        --code-width       600 \
        --refs             _data/refs.yml \
        --output-dir       ./md2-local \
        --asset-output-dir ./md2-local/ \
        --md-output        ./md2-local/$name-$platform-remote.md \
        --rewrite          "^$title/" "$url_base/$title/" \
        $fn

    cp assets/images/qrcode-hori.jpg ./md2-local/
    cp assets/css/github-markdown.css ./md2-local/

    # Build html
    md2html "./md2-local/$name-$platform.md"        "./md2-local/$name-$platform.html"
    md2html "./md2-local/$name-$platform-remote.md" "./md2-local/$name-$platform-remote.html"

    # Upload
    aws s3 sync ./md2-local/ s3://bed/

    echo "Built online md:"
    echo ""
    echo "    $url_base/$name-$platform.html"
    echo "    $url_base/$name-$platform-remote.html"
    echo ""
}

# build "wechat" _src/openraft-read/2023-12-17-openraft-read.md
# build "wechat" _src/calvin/2025-03-29-calvin.md
# build "zhihu" _src/calvin/2025-03-29-calvin.md
# build "wechat" _src/paxos-same-ballot/2025-04-13-paxos-same-ballot.md
# build "zhihu" _src/paxos-same-ballot/2025-04-13-paxos-same-ballot.md

# build "wechat" _src/single-log-joint/2025-04-19-single-log-joint.md
# build "zhihu" _src/single-log-joint/2025-04-19-single-log-joint.md

# build "wechat" _src/single-log-joint-png/2025-04-19-single-log-joint.md
# build "zhihu" _src/single-log-joint-png/2025-04-19-single-log-joint.md

# build "wechat" _src/crc/2025-08-27-crc.md
# build "wechat" _src/raft-io-order/2025-10-02-raft-io-order-cn.md

build "wechat" _src/raft-io-order/2025-10-09-raft-io-order-complete-cn.md
