def eq(a, b, walked=None):

    walked = walked or {}

    if (id(a), id(b)) in walked:
        return True

    walked[(id(a), id(b))] = True

    for k in set(a) | set(b):

        if k not in a or k not in b:
            return False

        if not eq(a[k], b[k], walked):
            return False

    return True

print eq({}, {'x':{}}) # False
print eq({'x': {}}, {'x':{}}) # True

a = {}
b = {}

a['x'] = a

b['x'] = {}
b['x']['x'] = b
print eq(a, b) # True
