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



def resource_to_image(fn, outdir, title, imgurl):
    '''
        Convert math and table to image.
        to make it easier to publish on other platform such wechat and weibo
    '''
    dd("convert: ", fn, " to dir: ", outdir, " title: ", title)
    imgdir = os.path.join(outdir, "images")
    mkdir(imgdir)

    with open(fn) as f:
        cont = f.read()

    cont = convert_math(cont, imgdir, imgurl)
    cont = convert_table(cont, imgdir, imgurl)

    with open(os.path.join(outdir, "index.html"), 'w') as f:
        f.write(cont)

patterns = (
        # block math
        (r'<script type="math/tex; mode=display">(.*?)</script>',
         '<img src="{src}" style="display: block; margin: 0 auto 1.3em auto" alt="{tex}"/>',
         True,
        ),

        # inline math
        (r'<script type="math/tex">(.*?)</script>',
         '<img src="{src}" style="height: 1.2em" alt="{tex}"/>',
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

tbl_patterns = (
        # block math
        (r'<table>.*?</table>',
         '<img src="{src}" style="display: block; margin: 0 auto 1.3em auto" alt="{alt}"/>',
        ),
)

def convert_table(cont, imgdir, imgurl):

    for ptn, repl in tbl_patterns:

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

            pngfn = table_to_image(tblhtml, imgdir)
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
        </style>
    </head>
    <body>
'''
tblhtml_end = '''
    </body>
</html>
'''

def table_to_image(tblhtml, imgdir):
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

def tex_to_image(tex, imgdir, is_block):

    texmd5 = hashlib.md5(tex).hexdigest()
    texescaped = re.sub('[^a-zA-Z0-9_\-=]+', '_', tex)
    fn = texescaped + '-' + texmd5 + '.png'
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
    # _site/tech/zipf/index.hml
    # _site/tech/zipf
    src = sys.argv[1]
    if not src.endswith('/index.html'):
        src = src.rstrip('/') + '/index.html'

    title = src.split('/')[-2]
    pubdir = 'publish'
    outdir = os.path.join(pubdir, title)
    imgurl = '/' + pubdir + '/' + title + '/images'
    resource_to_image(src, outdir, title, imgurl)
