#!/usr/bin/env python2
# coding: utf-8

import sys
import yaml

class IndexMaker(object):
    def __init__(self, name):
        self.name = name
        self.id2index = {}
        self.index = -1

    def get_index(self, x):
        i = self._get_index(x)
        return i

    def _get_index(self, x):

        if id(x) in self.id2index:
            return self.id2index[id(x)]

        self.index += 1
        self.id2index[id(x)] = self.index
        return self.index

class Node(dict):
    mapping = {}

    @classmethod
    def make(clz, index_maker, d, label=None, wrap=True):

        if id(d) in clz.mapping:
            rst = clz.mapping[id(d)]
            if label is not None:
                rst.label = label
        else:
            rst = Node(index_maker, d, label=label, wrap=wrap)

        return rst

    def __init__(self, index_maker, d, label=None, wrap=True):

        super(Node, self).__init__(d)

        self.data_dict = d
        self.name = index_maker.name
        self.index_maker = index_maker
        self.index = index_maker.get_index(self)

        if label is None:
            if self.index == 0:
                print "self.index is 0"
                self.label = self.name
            else:
                self.label = self.name + str(self.index)
        else:
            self.label = label

        if not wrap:
            return

        self.mapping[id(d)] = self
        q = [self]

        for n in q:

            for k in n:
                v = n[k]
                if isinstance(v, Node):
                    continue

                if id(v) in self.mapping:
                    n[k] = self.mapping[id(v)]
                else:
                    n[k] = Node.make(self.index_maker, v, wrap=False)
                    q.append(n[k])
                    self.mapping[id(v)] = n[k]


class Maker(object):

    def __init__(self, objects):

        self.pair_index_maker = IndexMaker('pair')

        self.objects = [
                # force label for root node
                [k, Node.make(IndexMaker(k), v, label=k)]
                for k, v in objects
        ]

        a, b = self.objects[0][1], self.objects[1][1]
        self.ab2pair = {}
        self.root = self.tensor_product(a, b)

    def _get_pair_node(self, a, b):

        ia, ib = id(a), id(b)
        k = (ia, ib)

        if k not in self.ab2pair:
            return None
        else:
            return self.ab2pair[k]

    def _make_pair_node(self, a, b):
        k = (id(a), id(b))
        pairnode = Node.make(self.pair_index_maker, {}, label=a.label + b.label)
        self.ab2pair[k] = pairnode
        return pairnode

    def tensor_product(self, a, b):

        pairnode = self._get_pair_node(a, b)
        if pairnode is not None:
            return pairnode

        pairnode = self._make_pair_node(a, b)

        branches = set(a) & set(b)

        for k in branches:
            av, bv = a[k], b[k]

            subpairnode = self.tensor_product(av, bv)
            pairnode[k] = subpairnode

        return pairnode

    def yaml(self):
        return yaml.dump(self.root)

    def dot(self, with_product=True):
        rst = []
        rst += ['strict digraph xp {']

        for k, v in self.objects:
            rst += self.graph(v)

        if with_product:
            rst += self.graph(self.root)

        rst += ['}']

        return '\n'.join(rst)

    def graph(self, n):

        rst = []
        accessed = {}

        q = [n]
        for p in q:

            if id(p) in accessed:
                continue

            accessed[id(p)] = True

            for k in p:

                line = '{x} -> {y} [label={l}]'.format(
                        x=p.label,
                        y=p[k].label,
                        l=k)
                rst += [line]

                q.append(p[k])

        return rst

if __name__ == "__main__":

    fn = sys.argv[1]
    with open(fn, 'r') as f:
        y = f.read()

    y = yaml.load(y)

    # print yaml.dump([['a', a], ['b', b]])
    # print Maker((('a', a), ('b', b))).yaml()
    # print yaml.dump(Maker(y[:2]).root)
    print Maker(y[:2]).dot(with_product=y[2].get('with_product', True))
