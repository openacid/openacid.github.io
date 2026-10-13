#!/usr/bin/env python
# coding: utf-8

import sys
import base64

if __name__ == "__main__":
    fn = sys.argv[1]

    with open(fn, 'r') as f:
        cont = f.read()

    datauri = "data:{};base64,{}".format('image/png',
                                         base64.b64encode(cont))
    img = '<img width="100%" src="{datauri}"/>'.format(
        datauri=datauri,
    )

    print img
