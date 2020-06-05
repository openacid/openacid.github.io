#!/usr/bin/env python2
# coding: utf-8

import hashlib
import os
import re
import proc
import sys

def dd(*msg):
    print ''.join([str(x) for x in msg])

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

    if 'math' in opt:
        cont = convert_math(cont, imgdir, imgurl)
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
    if 'a-to-txt' in opt:
        cont = convert_xxx(cont, a_to_txt_ptns)


    with open(os.path.join(outdir, "index.html"), 'w') as f:
        f.write(cont)

patterns = (
        # block math
        (r'<script type="math/tex; mode=display">(.*?)</script>',
         '<img src="{src}" style="display: block; margin: 0 auto 1.3em auto" _alt="{tex}"/>',
         True,
        ),

        # inline math
        (r'<script type="math/tex">(.*?)</script>',
         '<img src="{src}" style="height: 1.2em" _alt="{tex}"/>',
         False,
        ),
)

def convert_math(cont, imgdir, imgurl):

    for ptn, repl, is_block in patterns:

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
    proc.shell_script('rm *.png *.html', cwd=tmpdir)

    tblmd5 = hashlib.md5(tblhtml).hexdigest()
    fn = "tbl_" + tblmd5 + ".png"

    if os.path.exists(os.path.join(imgdir, fn)):
        return fn

    html = tblhtml_start + tblhtml + tblhtml_end
    with open(jp(tmpdir, "tbl.html"), 'w') as f:
        f.write(html)

    dd("make html at:", jp(tmpdir, "tbl.html"))
    proc.command_ex(
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
    proc.command_ex(
            "convert",
            "screenshot.png",
            "-trim",
            "+repage",
            jp(imgdir, fn),
            cwd=tmpdir,
    )

    proc.shell_script('rm *.png *.html', cwd=tmpdir)
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
            dd("### keep:  ",  inner)

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


def tex_to_image(tex, imgdir, is_block):

    texmd5 = hashlib.md5(tex).hexdigest()
    texescaped = re.sub('[^a-zA-Z0-9_\-=]+', '_', tex)
    fn = texescaped[:64] + '-' + texmd5 + '.png'
    fn = fn.lstrip('_')

    if os.path.exists(os.path.join(imgdir, fn)):
        return fn

    # texvc does not support '\\' as line-break.
    # tex_to_image_texvc(tex, imgdir, fn)
    tex_to_image_pdflatex(tex, imgdir, fn, is_block)

    return fn

def tex_to_image_pdflatex(tex, imgdir, fn, is_block):

    dst = os.path.join(imgdir, fn)

    # remove empty line those annoy pdflatex
    tex = re.sub('\n *\n', '\n', tex)
    tex = tex.strip()

    if is_block:
        # begin{equation} and $$ both starts a display-math block
        if tex.startswith('\\begin{equation}'):
            pass
        else:
            tex = '$$\n%s\n$$' % tex
    else:
        tex = '$' + tex + '$'

    tex = ('\\documentclass{article}\n'
           '\\pagestyle{empty}\n'
           '\\usepackage{amsmath}\n'
           '\\usepackage{amsfonts}\n'
           '\\usepackage[mathletters]{ucs}\n'
           '\\usepackage[utf8x]{inputenc}\n'
           '\\newcommand{\\lt}{<}\n'
           '\\newcommand{\\gt}{>}\n'
           '\\begin{document}\n'
           '%s\n'
           '\end{document}') % (tex, )

    basefn = 'xp-blog-tmp'
    texfn = basefn + '.tex'
    pdffn = basefn + '.pdf'
    croppedfn = basefn + '-crop.pdf'

    with open(texfn, 'w') as f:
        f.write(tex)

    proc.command_ex('pdflatex', texfn)
    proc.command_ex('pdfcrop', pdffn, croppedfn)
    rc, pngdata, err = proc.command_ex(
        'convert',
        '-density', '160',
        '-quality', '100',
        croppedfn, 'png:-'
    )

    with open(dst, 'w') as f:
        f.write(pngdata)


def tex_to_image_texvc(tex, imgdir, fn):

    # texvc: https://github.com/drmingdrmer/texvc
    code, out, err = proc.command_ex('texvc',
                    # tmpdir
                    ".",
                    imgdir,
                    tex,
                    "iso-8859-1"
    )

    # first output char is code:
    # texvc output format is like this:
    #    +%5		ok, but not html or mathml
    #    c%5%h	ok, conservative html, no mathml
    #    m%5%h	ok, moderate html, no mathml
    #    l%5%h	ok, liberal html, no mathml
    #    C%5%h\0%m	ok, conservative html, with mathml
    #    M%5%h\0%m	ok, moderate html, with mathml
    #    L%5%h\0%m	ok, liberal html, with mathml
    #    X%5%m	ok, no html, with mathml
    #    S		syntax error
    #    E		lexing error
    #    F%s		unknown function %s
    #    -		other error

    # \0 - null character
    # %5 - md5, 32 hex characters
    # %h - html code, without \0 characters
    # %m - mathml code, without \0 characters
    outfn = out[1:33]

    print "tex:", tex
    print "out:", out
    print "outfn:", outfn
    print "fn:", fn
    os.rename(os.path.join(imgdir, outfn + '.png'),
              os.path.join(imgdir, fn)
    )

    return fn


if __name__ == "__main__":

    opts = {
            'wechat': 'math       a-to-txt                        permlink',
            'weibo':  'math table          pre code blockquote    permlink li-p',
            'zhihu':  'math table          pre                 hr permlink'
    }

    # _site/tech/zipf/index.hml
    # _site/tech/zipf
    src = sys.argv[1]
    if not src.endswith('/index.html'):
        src = src.rstrip('/') + '/index.html'

    title = '/'.join(src.split('/')[1:-1])
    pubdir = 'publish'

    for plat4m, opt in opts.items():
        outdir = os.path.join(pubdir, plat4m, title)
        imgurl = '/' + pubdir + '/' + plat4m + '/' + title + '/images'

        resource_to_image(src, outdir, title, imgurl, opt)
