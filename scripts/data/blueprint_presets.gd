class_name BlueprintPresets
extends RefCounted
## 他人图纸：一键复刻的营地设计。
## 图纸只描述"想建成什么样"——能否建成仍取决于材料与地形（导入不等于通关）。

const LIST := [
	{
		"name": "火塘小屋",
		"author": "守灯人",
		"desc": "三面木墙一扇门，床、箱、火塘。最朴素的过夜法子。",
		"layout": [
			{"type": "wood_wall", "dx": 2.5, "dz": 0.0, "rot": 0.0},
			{"type": "wood_wall", "dx": -2.5, "dz": 0.0, "rot": 0.0},
			{"type": "wood_wall", "dx": 0.0, "dz": 2.5, "rot": 0.0},
			{"type": "wood_door", "dx": 0.0, "dz": -2.5, "rot": 0.0},
			{"type": "wood_roof", "dx": 0.0, "dz": 0.0, "rot": 0.0},
			{"type": "bed", "dx": 1.0, "dz": 1.2, "rot": 0.0},
			{"type": "storage", "dx": -1.2, "dz": 1.2, "rot": 0.0},
			{"type": "campfire", "dx": 0.0, "dz": -4.5, "rot": 0.0},
		],
	},
	{
		"name": "风雪堡垒",
		"author": "韩木",
		"desc": "石墙四间、石圈火塘、床箱俱全。扛得住周天灾的旧图纸。",
		"layout": [
			{"type": "stone_wall", "dx": 3.5, "dz": 0.0, "rot": 0.0},
			{"type": "stone_wall", "dx": -3.5, "dz": 0.0, "rot": 0.0},
			{"type": "stone_wall", "dx": 0.0, "dz": 3.5, "rot": 0.0},
			{"type": "stone_wall", "dx": 0.0, "dz": -3.5, "rot": 0.0},
			{"type": "wood_door", "dx": 3.5, "dz": 3.5, "rot": 0.0},
			{"type": "wood_roof", "dx": 0.0, "dz": 0.0, "rot": 0.0},
			{"type": "stone_fire", "dx": 0.0, "dz": -5.5, "rot": 0.0},
			{"type": "bed", "dx": 1.8, "dz": 1.8, "rot": 0.0},
			{"type": "storage", "dx": -1.8, "dz": 1.8, "rot": 0.0},
		],
	},
	{
		"name": "暖边火铺",
		"author": "苏一",
		"desc": "一张挨着火塘的床，一顶屋顶。解冻人、烤湿衣，都靠这一铺。",
		"layout": [
			{"type": "campfire", "dx": 0.0, "dz": -2.0, "rot": 0.0},
			{"type": "bed", "dx": 0.0, "dz": 1.0, "rot": 0.0},
			{"type": "wood_roof", "dx": 0.0, "dz": 0.0, "rot": 0.0},
			{"type": "snow_wall", "dx": 2.2, "dz": 0.0, "rot": 0.0},
			{"type": "snow_wall", "dx": -2.2, "dz": 0.0, "rot": 0.0},
			{"type": "snow_wall", "dx": 0.0, "dz": 2.2, "rot": 0.0},
		],
	},
]

static func all() -> Array:
	return LIST
