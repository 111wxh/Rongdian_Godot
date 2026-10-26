"""《融点》程序化资产生成器（Blender 4.2 headless）

用法：
  blender -b -P tools/blender/gen_assets.py -- --out="<项目绝对路径>/assets/models" [--only=dead_tree,ice_rock]

约定：
  * 单位 = 米，Z 轴向上（glTF 导出自动转 Y-up，与 Godot 一致）
  * 每个资产一个 .glb，原点在物体底面中心
  * 材质只用 Principled BSDF 的基础通道，细节交给 Godot 的 triplanar 覆雪着色器
"""

import bpy
import bmesh
import math
import random
import sys
import os
from mathutils import Vector, Matrix

# ----------------------------------------------------------------------------
# 命令行
# ----------------------------------------------------------------------------

def parse_args():
    out = None
    only = None
    for a in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []:
        if a.startswith("--out="):
            out = a[6:]
        elif a.startswith("--only="):
            only = set(a[7:].split(","))
    return out, only


# ----------------------------------------------------------------------------
# 基础工具
# ----------------------------------------------------------------------------

def new_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    sc.unit_settings.scale_length = 1.0
    return sc


def mesh_from_bm(bm, name):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def frames_along(points):
    """平行传输标架，避免管状体扭麻花。"""
    dirs = []
    n = len(points)
    for i in range(n):
        if i == 0:
            d = points[1] - points[0]
        elif i == n - 1:
            d = points[-1] - points[-2]
        else:
            d = points[i + 1] - points[i - 1]
        if d.length < 1e-7:
            d = Vector((0.0, 0.0, 1.0))
        dirs.append(d.normalized())
    up = Vector((0.0, 0.0, 1.0))
    n0 = dirs[0].cross(up)
    if n0.length < 1e-4:
        n0 = dirs[0].cross(Vector((1.0, 0.0, 0.0)))
    n0.normalize()
    first = (n0, dirs[0].cross(n0).normalized())
    out = [first]
    for i in range(1, n):
        q = dirs[i - 1].rotation_difference(dirs[i])
        a, b = out[-1]
        out.append(((q @ a).normalized(), (q @ b).normalized()))
    return out


def add_tube(bm, points, radii, seg=6, cap_start=True, cap_end=True):
    """沿折线生成变半径管。points/radii 等长。"""
    fr = frames_along(points)
    rings = []
    for i, p in enumerate(points):
        n, b = fr[i]
        r = radii[i]
        ring = []
        for k in range(seg):
            a = 2.0 * math.pi * k / seg
            ring.append(bm.verts.new(p + (n * math.cos(a) + b * math.sin(a)) * r))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(seg):
            k2 = (k + 1) % seg
            try:
                bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            except ValueError:
                pass
    if cap_end:
        try:
            bm.faces.new(tuple(reversed(rings[-1])))
        except ValueError:
            pass
    if cap_start:
        try:
            bm.faces.new(tuple(rings[0]))
        except ValueError:
            pass
    return rings


def add_box(bm, center, size, rot_euler=None):
    m = Matrix.Translation(Vector(center))
    if rot_euler:
        m = m @ rot_euler.to_matrix().to_4x4()
    m = m @ Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def add_ico(bm, center, radius, subdiv=1, scale=(1, 1, 1), rot=None):
    m = Matrix.Translation(Vector(center))
    if rot:
        m = m @ rot.to_matrix().to_4x4()
    m = m @ Matrix.Diagonal(Vector((scale[0], scale[1], scale[2], 1.0)))
    try:
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius, matrix=m)
    except TypeError:
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, diameter=radius, matrix=m)


def rot_from(axis, angle):
    return Matrix.Rotation(angle, 4, axis)


def finish(ob, name, mat, split_angle=38.0):
    ob.name = name
    ob.data.name = name + "_mesh"
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    # 平滑 + 按角度自动锐边
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.modifier_add(type='EDGE_SPLIT')
        ob.modifiers[-1].split_angle = math.radians(split_angle)
        bpy.ops.object.modifier_apply(modifier=ob.modifiers[-1].name)
    except Exception:
        pass
    ob.select_set(False)
    return ob


def mat(name, color, rough=0.85, metal=0.0, spec=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = spec
    return m


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_materials='EXPORT',
        export_texcoords=False,
        export_cameras=False,
        export_lights=False,
    )
    size = os.path.getsize(path) if os.path.exists(path) else 0
    print("EXPORTED %s  %d bytes" % (path, size))


# ----------------------------------------------------------------------------
# 资产：枯树（递归分叉、风蚀弯曲、断枝）
# ----------------------------------------------------------------------------

def build_dead_tree(seed, height=5.0, name="dead_tree"):
    rng = random.Random(seed)
    bm = bmesh.new()

    def grow(start, direction, length, radius, depth, pts_acc):
        n = 5 if depth > 1 else 4
        points = [start]
        radii = [radius]
        cur = start.copy()
        d = direction.normalized()
        for i in range(n):
            # 每段轻微随机偏航 + 重力下垂，形成风蚀的扭曲感
            d = (d + Vector((rng.uniform(-0.22, 0.22), rng.uniform(-0.22, 0.22), rng.uniform(-0.16, 0.02)))).normalized()
            cur = cur + d * (length / n)
            r = radius * (1.0 - (i + 1.0) / n * 0.62)
            points.append(cur.copy())
            radii.append(max(r, 0.006))
        add_tube(bm, points, radii, seg=7 if depth > 1 else 5)
        pts_acc.extend(points)
        if depth <= 0:
            return
        branches = rng.randint(2, 3)
        for _ in range(branches):
            t = rng.uniform(0.45, 0.92)
            idx = max(1, min(len(points) - 1, int(t * (len(points) - 1))))
            base = points[idx]
            base_r = radii[idx]
            az = rng.uniform(0.0, math.tau)
            tilt = rng.uniform(0.45, 0.95)
            side = Vector((math.cos(az), math.sin(az), 0.0))
            nd = (d + side * math.tan(tilt)).normalized()
            nd.z = max(nd.z, 0.05)
            nd.normalize()
            grow(base, nd, length * rng.uniform(0.52, 0.68), base_r * 0.66, depth - 1, pts_acc)

    trunk_r = height * 0.030
    grow(Vector((0, 0, 0)), Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), 1.0)),
         height * 0.42, trunk_r, 3, [])

    # 根部隆起
    for _ in range(3):
        a = rng.uniform(0, math.tau)
        add_ico(bm, (math.cos(a) * trunk_r * 2.2, math.sin(a) * trunk_r * 2.2, trunk_r * 0.6),
                trunk_r * rng.uniform(1.4, 2.0), 1, (1.3, 1.3, 0.6))

    ob = mesh_from_bm(bm, name)
    return finish(ob, name, mat("bark", (0.055, 0.048, 0.045), 0.92))


# ----------------------------------------------------------------------------
# 资产：冰岩（多面体 + 二次破碎面）
# ----------------------------------------------------------------------------

def _coherent(d, seed):
    """方向上的连续噪声：三组不同频率的正弦叠加。

    直接用 random.uniform 逐顶点推挤会得到一个长满尖刺的球——每个顶点
    各自乱跳，相邻面之间没有关联，法线因此碎成一片纸板。这里用方向的
    连续函数代替随机数，起伏才会连成块面。
    """
    rng = random.Random(seed)
    ph = [rng.uniform(0.0, math.tau) for _ in range(6)]
    n = 0.0
    n += math.sin(d.x * 3.1 + ph[0]) * math.cos(d.y * 2.7 + ph[1]) * 0.55
    n += math.sin(d.y * 5.3 + ph[2]) * math.cos(d.z * 4.7 + ph[3]) * 0.30
    n += math.sin(d.z * 8.9 + ph[4]) * math.cos(d.x * 9.7 + ph[5]) * 0.15
    return n


def build_ice_rock(seed, radius=1.4, name="ice_rock"):
    rng = random.Random(seed)
    bm = bmesh.new()
    try:
        bmesh.ops.create_icosphere(bm, subdivisions=3, radius=radius)
    except TypeError:
        bmesh.ops.create_icosphere(bm, subdivisions=3, diameter=radius)
    # 低频连续起伏 → 大块冰体的鼓包与凹面
    for v in bm.verts:
        d = v.co.normalized()
        f = 1.0 + _coherent(d, seed) * 0.26
        v.co = d * radius * f
        # 整体压扁成趴在地面的冰块，并顺风向拉长
        v.co.x *= rng.uniform(1.05, 1.30)
        v.co.y *= rng.uniform(0.82, 1.02)
        v.co.z *= rng.uniform(0.62, 0.86)
    bm.verts.ensure_lookup_table()
    # 把地面以下压平，让冰块像冻在地里
    for v in bm.verts:
        if v.co.z < -radius * 0.15:
            v.co.z = -radius * 0.15
    ob = mesh_from_bm(bm, name)
    return finish(ob, name, mat("ice", (0.42, 0.62, 0.78), 0.16), split_angle=62.0)


# ----------------------------------------------------------------------------
# 主流程
# ----------------------------------------------------------------------------

def main():
    out, only = parse_args()
    if out is None:
        out = os.path.join(os.getcwd(), "assets", "models")

    jobs = {
        "dead_tree": lambda: build_dead_tree(11, 5.2),
        "dead_tree_b": lambda: build_dead_tree(27, 3.6),
        "ice_rock": lambda: build_ice_rock(5, 1.6),
        "ice_rock_b": lambda: build_ice_rock(9, 1.0),
    }

    for name, fn in jobs.items():
        if only and name not in only:
            continue
        new_scene()
        fn()
        export_glb(os.path.join(out, name + ".glb"))


main()
