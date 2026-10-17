class_name RecipeBook
## Ingredients and recipes (data/recipes.json), menu items (data/menu.json), and judging a
## finished bowl. Only the right ingredients matter; a tidy bowl earns extra stars (customer mood only).

const FULL_ICE := 0.85   # fill at or above this counts as a full, tidy mound
const MIN_ICE := 0.25    # less than this is not a dessert yet

static var _ingredients := {}
static var _recipes := {}
static var _menu := {}


static func _load() -> void:
	if not _ingredients.is_empty():
		return
	var r: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json"))
	_ingredients = r.ingredients
	_recipes = r.recipes
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menu.json"))
	for item in m.items:
		_menu[item.id] = item


static func ingredient(id: String) -> Dictionary:
	_load()
	return _ingredients[id]


static func ingredient_name(id: String) -> String:
	return ingredient(id).name


static func color(id: String, key := "color") -> Color:
	var c: Array = ingredient(id).get(key, ingredient(id).color)
	return Color8(int(c[0]), int(c[1]), int(c[2]))


## Ingredient ids of one kind ("base", "topping", "side", "sauce"), sorted by slot.
static func of_kind(kind: String) -> Array[String]:
	_load()
	var out: Array[String] = []
	for id in _ingredients:
		if _ingredients[id].kind == kind:
			out.append(id)
	out.sort_custom(func(a, b): return _ingredients[a].get("slot", 0) < _ingredients[b].get("slot", 0))
	return out


static func recipe(item_id: String) -> Dictionary:
	_load()
	return _recipes[item_id]


## Which bowl a dessert is made in: "glass" (ice) or "soup".
static func vessel(item_id: String) -> String:
	return ingredient(recipe(item_id).base).vessel


static func has_recipe(item_id: String) -> bool:
	_load()
	return _recipes.has(item_id)


static func item_name(item_id: String) -> String:
	_load()
	return _menu[item_id].name


static func menu_item(item_id: String) -> Dictionary:
	_load()
	return _menu[item_id]


static func price(item_id: String) -> int:
	return int(menu_item(item_id).price)


## Shop price to add the item to the menu (cents), 0 if it is not for sale.
static func unlock_cost(item_id: String) -> int:
	return int(menu_item(item_id).get("unlock_cost", 0))


## Icon colour of a dessert (order bubbles).
static func item_color(item_id: String) -> Color:
	var c: Array = menu_item(item_id).color
	return Color8(int(c[0]), int(c[1]), int(c[2]))


## Menu ids that have a recipe the making view can build, in menu order.
static func makeable(start_unlocked_only := false) -> Array[String]:
	_load()
	var out: Array[String] = []
	for id in _menu:
		if _recipes.has(id) and (_menu[id].start_unlocked or not start_unlocked_only):
			out.append(id)
	return out


## Every ingredient the recipe needs, base first, as {id, done} rows for the order card.
static func checklist(item_id: String, bowl: Dictionary) -> Array:
	var r := recipe(item_id)
	var rows := [{"id": r.base, "done": bowl.base == r.base and bowl.fill >= MIN_ICE}]
	for t in r.toppings:
		rows.append({"id": t, "done": t in bowl.toppings})
	for s in r.sauces:
		rows.append({"id": s, "done": s in bowl.sauces})
	return rows


## bowl: {base, fill, toppings, sauces, fixes}. Returns {correct, stars (0-3), missing, extra}.
## Correct = right ice or soup, every topping and sauce, nothing else. Stars: 1 for correct,
## +1 for a full bowl (mound or soup), +1 when no topping had to be taken back out.
static func judge(item_id: String, bowl: Dictionary) -> Dictionary:
	var r := recipe(item_id)
	var missing: Array[String] = []
	var extra: Array[String] = []
	if bowl.base != r.base or bowl.fill < MIN_ICE:
		missing.append(r.base)
	if bowl.base != "" and bowl.base != r.base:
		extra.append(bowl.base)
	for t in r.toppings + r.sauces:
		if not (t in bowl.toppings or t in bowl.sauces):
			missing.append(t)
	for t in bowl.toppings + bowl.sauces:
		if not (t in r.toppings or t in r.sauces):
			extra.append(t)
	var correct := missing.is_empty() and extra.is_empty()
	var stars := 0
	if correct:
		stars = 1 + int(bowl.fill >= FULL_ICE) + int(bowl.fixes == 0)
	return {"correct": correct, "stars": stars, "missing": missing, "extra": extra}
