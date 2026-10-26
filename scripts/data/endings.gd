class_name Endings
extends RefCounted
## 多结局骨架：由营地水平、同行者数量、线索拼合度综合决定（不由倒计时决定）

const ENDINGS := {
	"extinguished": {
		"title": "熄灭",
		"text": "火灭了。\n风把灰烬收进雪里，像什么都不曾发生过。\n但在很远的地方，还有没熄的火——只要还有人醒着，就谈不上终结。",
	},
	"alone": {
		"title": "孤火",
		"text": "终端亮了，暖意以你的家为圆心动身。\n只有你一个人站在光里。\n火传出去了，路也打通了——走不走，是别人的事了。\n你守住这一盏，就算守住了火种。",
	},
	"home": {
		"title": "余烬之家",
		"text": "暖意一圈圈荡开，冰层发出低低的叹息。\n你的身边有了别人：火边多了几双影子，夜里多了几道呼吸。\n家还不大，但每一块砖都认得每一个人。\n余烬不灭，就能一点点烧成篝火。",
	},
	"rongdian": {
		"title": "融点",
		"text": "三座终端依次共鸣，声音传过冰原，像一声迟到万年的应答。\n你把散落的纸页按进面板，也把散落的人聚到了火边。\n冰在退。第一道融水汇成细流，朝着低处去。\n融点之名，从此有了实义。",
	},
	"true": {
		"title": "未命名（真结局）",
		"text": "所有纸页都亮了。所有该找回的人都回到了火边。\n郑工念出那句刻在断墙上的话：火不是一个人能传远的。\n冰原尽头，天光第一次有了温度。\n没有人给这一刻起过名字。\n也许，名字要留给下一个醒来的活人。",
	},
	# ---- E 系三假说结局（真相三分支）----
	"observer": {
		"title": "观察者（H1 自然耦合）",
		"text": "你选择「记录并离开」。\n热引擎被设为最低功耗，采集设备逐一关闭。\n逃生舱升空，镜头拉远——冰封星球在恒星微光下寂静运转。\n世界没有因为你的到来或离开发生任何改变。\n解锁 L3 元遗产「观察者之眼」：后续周目能以热力图看见环境的力学梯度。",
	},
	"restorer": {
		"title": "修复者（H2 干预失控）",
		"text": "你选择「关闭失控装置」。\n热引擎推至过载，热流涌入地下深处的自动调节器核心。\n震动与光芒之后，所有异常热源逐一熄灭。\n世界陷入真正的、彻底的寒冷与寂静——但不再有错误的指令。\n解锁 L3 元遗产「修复者之手」：后续周目可暂时降低局部热降解速率。",
	},
	"liberator": {
		"title": "解放者（H3 有意封存）",
		"text": "你选择「打破封存」。\n热引擎输出反向热脉冲，冰层深处的封存阵列逐一熄灭。\n被禁锢的能量与实体开始苏醒。\n世界没有变得温暖，而是变得「真实」——一种超越理解的、充满未知的新现实。\n解锁 L3 元遗产「解放者之钥」：后续周目可读取不可辨证据的底层元数据。",
	},
	"mixed": {
		"title": "中立观察者（三说之间）",
		"text": "三条假说的吻合度都在 30%-50% 之间——没有哪一个更能说服你。\n你带着这个自己知道、却无法消除的缺口，做出了最后一次选择。\n也许真相本来就不属于任何一个说法。\n它属于下一个带着温度计回到这里的人。",
	},
}

## 营地结局（由庇护所/同伴/线索决定，兼容原判定）
static func evaluate() -> String:
	var g_ev: Node = _g()
	var comp: int = int(g_ev.get("companions").size()) if g_ev else 0
	var clues: int = int(g_ev.get("clues").size()) if g_ev else 0
	var lv: int = int(g_ev.get("shelter_level")) if g_ev else 0
	if comp >= 6 and clues >= 12 and lv >= 5:
		return "true"
	if comp >= 4 and clues >= 8 and lv >= 4:
		return "rongdian"
	if comp >= 1:
		return "home"
	return "alone"

## 真相结局（由 E 系证据吻合度决定；≥85 分解锁接管选择）
static func evaluate_truth() -> String:
	var c := Evidence.all_coherence()
	var h1: float = c.get("h1", 0.0)
	var h2: float = c.get("h2", 0.0)
	var h3: float = c.get("h3", 0.0)
	# 混合结局：三说均在 30%-50% 无明显倾向
	if h1 >= 0.3 and h1 <= 0.5 and h2 >= 0.3 and h2 <= 0.5 and h3 >= 0.3 and h3 <= 0.5:
		return "mixed"
	var best := ""
	var best_v := 0.6
	if h1 > best_v: best = "observer"; best_v = h1
	if h2 > best_v: best = "restorer"; best_v = h2
	if h3 > best_v: best = "liberator"; best_v = h3
	if best == "":
		return "mixed"
	return best

## 证据完整度修正（≥12 全知 / <6 盲目）
static func completeness_note() -> String:
	var n := Evidence.held_count()
	if n >= 12:
		return "（证据全知：你读完了能读到的一切）"
	if n < 6:
		return "（证据盲目：更多的纸页散落在冰原某处）"
	return ""

static func entry(id: String) -> Dictionary:
	return ENDINGS.get(id, ENDINGS.alone)

static func death_id() -> String:
	return "extinguished"

## autoload「Game」在编译期不可见（本类被 game.gd 依赖，形成解析环），
## 运行时按 /root/Game 取节点。所有 static 函数统一走这里。
static func _g() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Game") if Engine.get_main_loop() else null
