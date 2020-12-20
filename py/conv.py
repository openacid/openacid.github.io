#!/usr/bin/env python2
# coding: utf-8

import hashlib
import os
import re
import urllib.parse
import k3proc
import k3down2
import sys

default_encoding = sys.getdefaultencoding()
if hasattr(sys, 'getfilesystemencoding'):
    default_encoding = sys.getfilesystemencoding()

def dd(*msg):
    print(''.join([str(x) for x in msg]))

def tobytes(s):
    return bytes(s, default_encoding)

def jp(*ps):
    return os.path.join(*ps)

def mkdir(*d):
    try:
        os.makedirs(os.path.join(*d))
    except OSError as e:
        if e.errno == 17:
            pass
        else:
            raise

tbl_patterns = (
        # block math
        (r'<table>.*?</table>',
         '<img src="{src}" style="display: block; margin: 0 auto 1.3em auto" _alt="{alt}"/>',
        ),
)

pre_patterns = (
        # block math
        (r'<pre.*?>.*?</pre>',
         '<img src="{src}" style="display: block; margin: 0 auto 1.3em auto" _alt="{alt}"/>',
        ),
)

blockquote_ptns = (
        (r'<blockquote>(.*?)</blockquote>',
         '{txt}'
        ),
)
code_ptns = (
        (r'<code.*?>(.*?)</code>',
         '{txt}'
         # '<span>{txt}</span>'
        ),
)
hr_ptns = (
        (r'<hr */>',
         # remove <hr/>
         '',
        ),
)
permlink_ptns = (
        (r'</body>(.*?)',
         # convert /body> to /body > thus it wont match twice
         '<style> .header-link {{ display: none !important; }} </style> </body >{txt}'
        ),
)
li_p_ptns = (
        (r'<li>\s*?<p>(.*?)</p>',
         '<li><b>{txt}</b>'
        ),
        (r'<li>(.*?)</li>',
         '{txt}'
        ),
)

#  add margin-top to h1 h2 ...
h_margin_ptns = (
        (r'([^>]|^)<h1 id=',
         '{txt}<br/><h1 id='
        ),
        (r'([^>]|^)<h2 id=',
         '{txt}<br/><h2 id='
        ),
        (r'([^>]|^)<h3 id=',
         '{txt}<br/><h3 id='
        ),
)

def handle_a_to_txt(sess, cont, m):

    s = m.start()
    e = m.end()
    txt = m.group("txt")
    href = m.group("href")
    sess[txt] = href

    newtxt = '[{txt}]'.format(txt=txt)

    dd("capture link:", txt, href)
    return cont[:s] + newtxt + cont[e:]

def a_to_txt_final(sess, cont):
    ptn = r'<ul class="page-links" style="display:none;">'
    m = re.search(ptn, cont, flags=re.DOTALL| re.UNICODE)
    if m is None:
        return

    s = m.start()
    e = m.end()

    newtxt = '<ul class="page-links" style="display:block;">'
    return cont[:s] + newtxt + cont[e:]

a_to_txt_ptns = (
        (r'<a href="(?P<href>.*?)".*?>(?P<txt>.*?)</a>',
         handle_a_to_txt,
         a_to_txt_final,
        ),
)


def resource_to_image(fn, outdir, title, imgurl, opt):
    '''
        Convert math and table to image.
        to make it easier to publish on other platform such wechat and weibo
    '''
    dd("convert: ", fn, " to dir: ", outdir, " title: ", title)
    imgdir = os.path.join(outdir, "images")
    mkdir(imgdir)

    with open(fn) as f:
        cont = f.read()

    opt = opt.split()

    if 'zhihumath' in opt:
        cont = convert_tex_to_zhihulink(cont, imgdir, imgurl)
    if 'math' in opt:
        cont = convert_tex_to_img(cont, imgdir, imgurl)
    if 'table' in opt:
        cont = convert_html_to_image(cont, imgdir, imgurl, tbl_patterns)
    if 'pre' in opt:
        cont = convert_html_to_image(cont, imgdir, imgurl, pre_patterns)
    if 'code' in opt:
        cont = convert_ptn(cont, code_ptns)
    if 'blockquote' in opt:
        cont = convert_ptn(cont, blockquote_ptns)
    if 'hr' in opt:
        cont = convert_ptn(cont, hr_ptns)
    if 'permlink' in opt:
        cont = convert_ptn(cont, permlink_ptns)
    if 'li-p' in opt:
        cont = convert_ptn(cont, li_p_ptns)
    if 'h-margin' in opt:
        cont = convert_ptn(cont, h_margin_ptns)
    if 'a-to-txt' in opt:
        cont = convert_xxx(cont, a_to_txt_ptns)


    with open(os.path.join(outdir, "index.html"), 'w') as f:
        f.write(cont)

zhihu_math_link = '{newline}<img src="https://www.zhihu.com/equation?tex={texurl}{alignment}" alt="{tex}" class="ee_img tr_noresize" eeimg="1">{newline}'
mathjax_to_zhihulink_patterns = (
        # block math
        (r'<script type="math/tex; mode=display">% <!\[CDATA\[(.*?)%]]></script>',
         True,
        ),
        (r'<script type="math/tex; mode=display">(.*?)</script>',
         True,
        ),

        # inline math
        (r'<script type="math/tex">(.*?)</script>',
         False,
        ),
)

def convert_tex_to_zhihulink(cont, imgdir, imgurl):

    for ptn, block in mathjax_to_zhihulink_patterns:

        while True:
            m = re.search(ptn, cont, flags=re.DOTALL| re.UNICODE)
            if m is None:
                break

            s = m.start()
            e = m.end()
            tex = m.groups()[0]
            dd()
            dd("### convert tex to zhihulink... ", block)
            dd("    ",  tex)

            tex = re.sub(r'\n', '', tex)
            dd("    tex: ", tex)

            imgtag = k3down2.tex_to_zhihu(tex, block)

            dd("    rendered zhihulink: ", imgtag)

            cont = cont[:s] + imgtag + cont[e:]

    return cont

mathjax_patterns = (
        # block math
        (r'<script type="math/tex; mode=display">% <!\[CDATA\[(.*?)%]]></script>',
         '<img src="{src}" style="zoom: 60%; display: block; margin: 0 auto 1.3em auto" _alt="{tex}"/>',
         True,
        ),

        (r'<script type="math/tex; mode=display">(.*?)</script>',
         '<img src="{src}" style="zoom: 60%; display: block; margin: 0 auto 1.3em auto" _alt="{tex}"/>',
         True,
        ),

        # inline math
        (r'<script type="math/tex">(.*?)</script>',
         '<img src="{src}" style="height: 0.8em" _alt="{tex}"/>',
         False,
        ),
)

def convert_tex_to_img(cont, imgdir, imgurl):

    for ptn, repl, is_block in mathjax_patterns:

        while True:
            m = re.search(ptn, cont, flags=re.DOTALL| re.UNICODE)
            if m is None:
                break

            s = m.start()
            e = m.end()
            tex = m.groups()[0]
            dd()
            dd("### convert tex... block mode:", is_block)
            dd("    ",  tex)

            pngfn = tex_to_image(tex, imgdir, is_block)
            dd("    image fn: ", pngfn)

            imgtag = repl.format(
                    src=imgurl+"/"+pngfn,
                    tex=tex)

            dd("    tag: ", imgtag)

            cont = cont[:s] + imgtag + cont[e:]

    return cont

def convert_html_to_image(cont, imgdir, imgurl, ptns):

    for ptn, repl in ptns:

        while True:
            m = re.search(ptn, cont, flags=re.DOTALL| re.UNICODE)
            if m is None:
                break

            s = m.start()
            e = m.end()
            tblhtml = cont[s:e]

            dd()
            dd("### convert table... ")
            dd("    ",  tblhtml)

            pngfn = html_to_image(tblhtml, imgdir)
            dd("    image fn: ", pngfn)

            imgtag = repl.format(
                    src=imgurl+"/"+pngfn,
                    alt="table")

            dd("    tag: ", imgtag)

            cont = cont[:s] + imgtag + cont[e:]

    return cont

tblhtml_start = '''<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
        <title>x</title>
        <style type="text/css" media="screen">
            table {
                display: block;
                margin-bottom: 1em;
                width: fit-content;
                font-family: -apple-system,BlinkMacSystemFont,"Roboto","Segoe UI","Helvetica Neue","Lucida Grande",Arial,sans-serif;
                font-size: .75em;
                border-collapse: collapse;
                overflow-x: auto;
            }

            thead {
                background-color: #ddd;
                border-bottom: 2px solid #ddd;
            }

            th {
                padding: 0.5em;
                font-weight: bold;
                text-align: left;
            }

            td {
                padding: 0.5em;
                border-bottom: 1px solid #ddd;
            }

            tr,
            td,
            th {
                vertical-align: middle;
            }
            pre.highlight {
                margin: 0;
                padding: 1em;
                background: #263238;
                color: #eff;
                font-size: 1.5em;
                font-family: "SFMono-Regular",Consolas,"Liberation Mono",Menlo,Courier,"PingFang SC", "Microsoft YaHei",monospace;
            }
        </style>
    </head>
    <body>
'''
tblhtml_end = '''
    </body>
</html>
'''

def html_to_image(tblhtml, imgdir):
    imgdir = os.path.abspath(imgdir)
    tmpdir = os.path.abspath("tmp")
    k3proc.shell_script('rm *.png *.html', cwd=tmpdir)

    tblmd5 = hashlib.md5(tobytes(tblhtml)).hexdigest()
    fn = "tbl_" + tblmd5 + ".png"

    if os.path.exists(os.path.join(imgdir, fn)):
        return fn

    html = tblhtml_start + tblhtml + tblhtml_end
    with open(jp(tmpdir, "tbl.html"), 'w') as f:
        f.write(html)

    dd("make html at:", jp(tmpdir, "tbl.html"))
    k3proc.command_ex(
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "--headless",
            "--screenshot",
            "--window-size=1000,2000",
            "--default-background-color=0",
            "tbl.html",
            cwd=tmpdir,
    )

    # TODO extend to match page width
    dd("crop to visible area")
    k3proc.command_ex(
            "convert",
            "screenshot.png",
            "-trim",
            "+repage",
            jp(imgdir, fn),
            cwd=tmpdir,
    )

    k3proc.shell_script('rm *.png *.html', cwd=tmpdir)
    return fn

def convert_ptn(cont, ptns):

    for ptn, repl in ptns:

        while True:
            m = re.search(ptn, cont, flags=re.DOTALL| re.UNICODE)
            if m is None:
                break

            s = m.start()
            e = m.end()
            gs = m.groups()
            if len(gs) > 0:
                inner = gs[0]
            else:
                inner = ''

            dd()
            dd("### remove:" + ptn)
            dd("### keep:  ",  repr(inner))

            newtxt = repl.format(
                    txt=inner)

            cont = cont[:s] + newtxt + cont[e:]

    return cont

def convert_xxx(cont, ptns):

    for ptn, repl, final in ptns:

        sess = {}

        while True:
            m = re.search(ptn, cont, flags=re.DOTALL| re.UNICODE)
            if m is None:
                break

            cont = repl(sess, cont, m)

        cont = final(sess, cont)

    return cont

def tex_fn(tex):
    '''
    Build a path base on base for tex image
    '''
    texmd5 = hashlib.md5(tobytes(tex)).hexdigest()
    texescaped = re.sub('[^a-zA-Z0-9_\-=]+', '_', tex)
    fn = texescaped[:64] + '-' + texmd5 + '.png'
    fn = fn.lstrip('_')
    return fn


def tex_to_image(tex, imgdir, is_block):

    fn = tex_fn(tex)

    if os.path.exists(os.path.join(imgdir, fn)):
        return fn

    k3down2.tex_to_png(tex, is_block, outputfn=jp(imgdir, fn))

    return fn


if __name__ == "__main__":

    opts = {
            'wechat': '           math       a-to-txt                        permlink',
            'weibo':  '           math table          pre code blockquote    permlink li-p h-margin',
            'zhihu':  'zhihumath       table          pre                 hr permlink',
            'import': '           math table          pre                            ',
    }

    # _site/tech/zipf/index.hml
    # _site/tech/zipf
    src = sys.argv[1]
    if not src.endswith('/index.html'):
        src = src.rstrip('/') + '/index.html'

    title = '/'.join(src.split('/')[1:-1])
    pubdir = 'publish'

    for plat4m, opt in list(opts.items()):
        outdir = os.path.join(pubdir, plat4m, title)
        imgurl = '/' + pubdir + '/' + plat4m + '/' + title + '/images'

        resource_to_image(src, outdir, title, imgurl, opt)
