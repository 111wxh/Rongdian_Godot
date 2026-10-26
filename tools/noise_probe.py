import math


def frac(x):
    return x - math.floor(x)


def h21(px, py):
    px = frac(px * 123.34)
    py = frac(py * 456.21)
    d = px * (px + 45.32) + py * (py + 45.32)
    px2 = px + d
    py2 = py + d
    return frac(px2 * py2)


def vn(px, py):
    ix = math.floor(px)
    iy = math.floor(py)
    fx = px - ix
    fy = py - iy
    ux = fx * fx * (3 - 2 * fx)
    uy = fy * fy * (3 - 2 * fy)
    a = h21(ix, iy)
    b = h21(ix + 1, iy)
    c = h21(ix, iy + 1)
    d = h21(ix + 1, iy + 1)
    ab = a + (b - a) * ux
    cd = c + (d - c) * ux
    return ab + (cd - ab) * uy


def fbm(px, py, oct_):
    v = 0.0
    a = 0.5
    for _ in range(oct_):
        v += vn(px, py) * a
        px = px * 2.03 + 19.3
        py = py * 2.03 + 7.7
        a *= 0.5
    return v


def dens_at(px, py):
    n = fbm(px * 0.60, py * 0.60, 4)
    n2 = fbm(px * 1.65 + 3.1, py * 1.65 + 3.1, 4)
    streak = fbm(px * 0.30, py * 2.05, 3)
    return (n - 0.5) * 2.05 + (n2 - 0.5) * 1.15 + (streak - 0.5) * 0.85 + 0.5


vals = []
for i in range(40):
    for j in range(40):
        vals.append(dens_at(i * 0.12, j * 0.12))
vals.sort()
n = len(vals)
print("min %.3f  p10 %.3f  p50 %.3f  p75 %.3f  p90 %.3f  max %.3f" % (
    vals[0], vals[n // 10], vals[n // 2], vals[n * 3 // 4], vals[n * 9 // 10], vals[-1]))
thr = 0.595 + (0.305 - 0.595) * 0.34
print("thr=%.3f  coverage=%.1f%%" % (thr, 100.0 * sum(1 for v in vals if v > thr) / n))
