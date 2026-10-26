class_name RecipeBook
## Ingredients and recipes (data/recipes.json), menu items (data/menu.json), and judging a
## finished bowl. Only the right ingredients matter; a tidy bowl earns extra stars (customer mood only).

const FULL_ICE := 0.85   # fill at or above this counts as a full, tidy mound
const MIN_ICE := 0.25    # less than this is not a dessert yet
const TOO_MUCH_ICE := 0.6   # cold soup: this much shaved ice or more in the soup bowl costs a star

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


## cold: the cold version (bobo chacha): its "ice" key names the shaved ice (the recipe's
## "cold_ice") that goes in the soup bowl too. Recipes without "ice" want none in a soup.
static func recipe(item_id: String, cold := false) -> Dictionary:
	_load()
	var r: Dictionary = _recipes[item_id]
	if cold and r.has("cold_ice"):
		r = r.duplicate(true)
		r.ice = r.cold_ice
	return r


## True if the dessert can also be ordered cold.
static func has_cold(item_id: String) -> bool:
	_load()
	return _recipes.has(item_id) and _recipes[item_id].has("cold_ice")


## Order name, "Cold bobo chacha" for a cold order.
static func order_name(item_id: String, cold := false) -> String:
	return ("Cold " + item_name(item_id).to_lower()) if cold else item_name(item_id)


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


## Every menu id in lightbox order (menu.json "no").
static func board() -> Array[String]:
	_load()
	var out: Array[String] = []
	out.assign(_menu.keys())
	out.sort_custom(func(a, b): return int(_menu[a].no) < int(_menu[b].no))
	return out


## Every ingredient the recipe needs, base first, as {id, done} rows for the order card.
static func checklist(item_id: String, bowl: Dictionary, cold := false) -> Array:
	var r := recipe(item_id, cold)
	var rows := [{"id": r.base, "done": bowl.base == r.base and bowl.fill >= MIN_ICE}]
	if r.has("ice"):
		rows.append({"id": r.ice, "done": bowl.get("ice", 0.0) > 0.0})
	for t in r.toppings:
		rows.append({"id": t, "done": t in bowl.toppings})
	for s in r.sauces:
		rows.append({"id": s, "done": s in bowl.sauces})
	return rows


## bowl: {vessel, base, fill, ice, toppings, sauces, fixes}. Returns {correct, stars (0-3), missing, extra}.
## Correct = right ice or soup, every topping and sauce, nothing else. Stars: 1 for correct,
## +1 for a full bowl (mound or soup), +1 when no topping had to be taken back out.
## A cold soup needs some shaved ice (a full mound of it, TOO_MUCH_ICE, costs a star); shaved
## ice in a warm soup is extra.
static func judge(item_id: String, bowl: Dictionary, cold := false) -> Dictionary:
	var r := recipe(item_id, cold)
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
	var ice: float = bowl.get("ice", 0.0)
	if r.has("ice") and ice <= 0.0:
		missing.append(r.ice)
	elif not r.has("ice") and ice > 0.0:
		extra.append("ice")
	var correct := missing.is_empty() and extra.is_empty()
	var stars := 0
	if correct:
		stars = 1 + int(bowl.fill >= FULL_ICE) + int(bowl.fixes == 0)
		if ice >= TOO_MUCH_ICE:
			stars = maxi(stars - 1, 1)
	return {"correct": correct, "stars": stars, "missing": missing, "extra": extra}
