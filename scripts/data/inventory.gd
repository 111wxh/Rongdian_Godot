class_name Inventory
extends RefCounted
## 背包：槽位堆叠 + 容量（背包道具 +10）

var slots: Array[Dictionary] = []   # {"id": String, "count": int}
const STACK_MAX := 20

func capacity() -> int:
	# Game 是 autoload 单例；编译期受解析环影响不可直接引用，
	# 运行时按 /root/Game 取节点（语义与原写法一致）
	# 开局只有身上几个口袋（DV.INV_BASE_SLOTS）；搜刮到背包才扩容（每个 +INV_BACKPACK_SLOTS）
	var ml := Engine.get_main_loop()
	var g_cap: Node = ml.root.get_node_or_null("Game") if ml else null
	if g_cap != null:
		return DV.INV_BASE_SLOTS + DV.INV_BACKPACK_SLOTS * int(g_cap.call("count_item", "backpack"))
	return DV.INV_BASE_SLOTS

func add(id: String, n: int = 1) -> int:
	var left := n
	for s in slots:
		if s.id == id and s.count < STACK_MAX:
			var take: int = mini(STACK_MAX - s.count, left)
			s.count += take
			left -= take
			if left <= 0:
				return 0
	while left > 0 and slots.size() < capacity():
		var take2: int = mini(STACK_MAX, left)
		slots.append({"id": id, "count": take2})
		left -= take2
	return left

func remove(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	var left := n
	var i := slots.size() - 1
	while i >= 0 and left > 0:
		var s: Dictionary = slots[i]
		if s.id == id:
			var take: int = mini(s.count, left)
			s.count -= take
			left -= take
			if s.count <= 0:
				slots.remove_at(i)
		i -= 1
	return left <= 0

func count(id: String) -> int:
	var total := 0
	for s in slots:
		if s.id == id:
			total += s.count
	return total

## 已占用槽位数（满载判据）
func used() -> int:
	return slots.size()

func has(id: String, n: int = 1) -> bool:
	return count(id) >= n

func aggregated() -> Array:
	## 返回 [{id, count}]，供 UI 展示
	var agg := {}
	for s in slots:
		agg[s.id] = agg.get(s.id, 0) + s.count
	var out := []
	for id in agg:
		out.append({"id": id, "count": agg[id]})
	out.sort_custom(func(a, b): return Items.name_of(a.id) < Items.name_of(b.id))
	return out

func first_of_cat(cat: String) -> String:
	for s in slots:
		if Items.cat_of(s.id) == cat:
			return s.id
	return ""

func to_dict() -> Dictionary:
	var out := []
	for s in slots:
		out.append({"id": s.id, "count": s.count})
	return {"slots": out}

func from_dict(d: Dictionary) -> void:
	slots.clear()
	for s in d.get("slots", []):
		slots.append({"id": s.id, "count": s.count})
