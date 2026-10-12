def eq(a, b):

    for k in set(a) | set(b):

        if k not in a or k not in b:
            return False

        if not eq(a[k], b[k]):
            return False

    return True

print eq({}, {'x':{}}) # False
print eq({'x':{}}, {'x':{}}) # True
