extends SceneTree

# Exercises the Merchant/shop/quest backend (NpcService) the way the new shop
# UI (game_hud.gd _refresh_shop_panel / _on_buy_pressed / _on_sell_held_pressed
# / _on_quest_turn_in_pressed) calls into it, without needing a full world
# boot - InventoryModel/ProgressionSystem/NpcService are pure gameplay state.

var _failures: Array[String] = []


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s (%s)" % [name, detail])
	else:
		_failures.append(name)
		print("FAIL %s (%s)" % [name, detail])


func _initialize() -> void:
	var inv := InventoryModel.new()
	var prog := ProgressionSystem.new()
	var service := NpcService.new(inv, prog)

	var merchant_profile: NpcProfile = service.profiles.get(&"merchant")
	_check("merchant profile loads from data/npc", merchant_profile != null, "profiles=%d" % service.profiles.size())

	var npc := NpcBase.new()
	npc.npc_name = "Merchant"
	npc.display_name = "Merchant"
	npc.shop_items = merchant_profile.shop_items.duplicate() if merchant_profile != null else []
	npc.quest_id = &"ore_delivery"

	_check("not resident before housing", not service.is_resident(npc), "")
	_check("shop closed before housing", not service.can_offer_shop(npc), "")
	_check("house_npc succeeds", service.house_npc(npc), "")
	_check("resident after housing", service.is_resident(npc), "")
	_check("shop open after housing", service.can_offer_shop(npc), "")

	inv.add_item(&"coin", 100)
	var torch_cost := service.price(&"torch")
	_check("can afford a torch", service.can_buy(npc, &"torch", 1), "cost=%d" % torch_cost)
	_check("buy succeeds", service.buy(npc, &"torch", 1), "")
	_check("inventory has the torch", inv.count(&"torch") == 1, "count=%d" % inv.count(&"torch"))
	_check("coins were deducted", inv.count(&"coin") == 100 - torch_cost, "coin=%d" % inv.count(&"coin"))

	inv.add_item(&"copper_ore", 10)
	_check("quest completable with enough ore", service.can_complete(npc), "")
	var before_coin := inv.count(&"coin")
	_check("quest completes", service.complete_quest(npc), "")
	_check("quest consumed 6 ore", inv.count(&"copper_ore") == 4, "left=%d" % inv.count(&"copper_ore"))
	_check("quest paid 60 coin", inv.count(&"coin") == before_coin + 60, "coin=%d" % inv.count(&"coin"))
	_check("quest paid 2 healing salves", inv.count(&"healing_salve") == 2, "count=%d" % inv.count(&"healing_salve"))
	_check("quest set its unlock flag", prog.has_flag(&"watch_friend"), "")
	_check("quest cannot be repeated", service.available_quest(npc) == null, "")

	_check("sell succeeds", service.sell(&"torch", 1), "")
	_check("torch is gone after selling", inv.count(&"torch") == 0, "count=%d" % inv.count(&"torch"))

	npc.free()

	if _failures.is_empty():
		print("NPC SHOP CHECK PASS")
		quit(0)
	else:
		print("NPC SHOP CHECK FAIL: %s" % ", ".join(_failures))
		quit(1)
