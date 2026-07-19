G.E_MANAGER.queues.Balatest = {}
G.E_MANAGER.queues.Balatest_Run = {}

local function protect(f, t)
	return function()
		if not t and Balatest.internal.abort then
			return true
		end
		local res, ret = pcall(f)
		if not res and not Balatest.done[Balatest.current_test] then
			Balatest.internal.abort = ret or true
		end
		return not res or ret ~= false
	end
end
local function protect_ev(f, t)
	if type(f) == "table" then
		if getmetatable(f) ~= Event then
			f = Event(f)
		end
		f.func = protect(f.func, t)
	elseif type(f) == "function" then
		f = Event({ no_delete = true, func = protect(f, t) })
	else
		error("Expected a function or event, got a " .. type(f), 3)
	end
	f.created_on_pause = true
	return f
end

--- Queues a test-level event. Works similarly to `Balatest.q()`.
--- @param f (fun():boolean?)|Event The event or a function to turn into an event.
--- @param front boolean|nil `true` to add the event to the front of the queue, rather than the end.
function Balatest.internal.tq(f, front)
	G.E_MANAGER:add_event(protect_ev(f, true), "Balatest", front)
end

--- Queues an event to be run during this test.
--- Note that events added this way implicitly `return true` unless you explicitly `return false`, unlike the vanilla ones.
--- @param f (fun():boolean?)|Event The event or a function to turn into an event.
--- @param front boolean|nil `true` to add the event to the front of the queue, rather than the end.
function Balatest.q(f, front)
	G.E_MANAGER:add_event(protect_ev(f), "Balatest_Run", front)
end

--- @alias State number A state in G.STATES
--- Queues an event to wait for manual input to be possible.
--- @param state (State|State[])? If set, also waits for the game to reach this state or one of these states.
--- @param front boolean? Forwarded to `Balatest.q`.
function Balatest.wait_for_input(state, front)
	Balatest.q(function()
		local state_done = G.STATE_COMPLETE
		if type(state) == "number" then
			state_done = G.STATE == state and G.STATE_COMPLETE
		elseif type(state) == "table" then
			state_done = false
			for _, s in pairs(state) do
				if G.STATE == s then
					state_done = G.STATE_COMPLETE
				end
			end
		end
		return Balatest.internal.abort
			or (state_done and not G.CONTROLLER.locked and not (G.GAME.STOP_USE and G.GAME.STOP_USE > 0))
	end, front)
end

--- Waits until the specified function does not return `nil`.
---@generic T any The type returned.
---@param func T|fun():T The funtion to wait on.
---@return fun():T A new function that returns the non-nil value generated.
function Balatest.internal.ensure_not_nil(func)
	if type(func) ~= "function" then
		return function()
			return func
		end
	end
	local ret = nil
	Balatest.q(function()
		ret = func()
		return ret ~= nil
	end)
	return function()
		return ret
	end
end

--- Starts the next blind from the blind select screen.
---@param with_blind? string|fun():string The blind to go to.
function Balatest.start_round(with_blind)
	Balatest.wait_for_input(G.STATES.BLIND_SELECT)
	with_blind = Balatest.internal.ensure_not_nil(with_blind)
	Balatest.q(function()
		if Balatest.internal.abort then
			return
		end
		G.FUNCS.select_blind({
			config = { ref_table = G.P_BLINDS[with_blind() or Balatest.current_test_object.blind or "bl_small"] },
			UIBox = { get_UIE_by_ID = function() end },
		})
	end)
	Balatest.wait_for_input(G.STATES.SELECTING_HAND)
end

--- Skips the next blind for the specified tag.
--- @param for_tag string|fun():string The tag ID that will spawn.
function Balatest.skip_blind(for_tag)
	Balatest.wait_for_input(G.STATES.BLIND_SELECT)
	for_tag = Balatest.internal.ensure_not_nil(for_tag)
	Balatest.q(function()
		if Balatest.internal.abort then
			return
		end
		G.FUNCS.skip_blind({
			UIBox = {
				get_UIE_by_ID = function()
					return { config = { ref_table = Tag(for_tag()) } }
				end,
			},
		})
	end)
	Balatest.wait_for_input(G.STATES.BLIND_SELECT)
end

--- Ends the current round as though the blind was won and goes to the results screen.
function Balatest.end_round()
	Balatest.wait_for_input({ G.STATES.SELECTING_HAND, G.STATES.ROUND_EVAL })
	Balatest.q(function()
		if Balatest.internal.abort or G.STATE == G.STATES.ROUND_EVAL then
			return
		end
		G.GAME.chips = G.GAME.blind.chips
		G.STATE = G.STATES.NEW_ROUND
		G.STATE_COMPLETE = false
	end)
	Balatest.wait_for_input(G.STATES.ROUND_EVAL)
end

--- Cashes out from the results screen and goes to the shop.
function Balatest.cash_out()
	Balatest.wait_for_input(G.STATES.ROUND_EVAL)
	Balatest.q(function()
		if Balatest.internal.abort then
			return
		end
		G.FUNCS.cash_out({ config = {} })
	end)
	Balatest.wait_for_input(G.STATES.SHOP)
end

--- Exits the shop and goes to the blind select screen.
function Balatest.exit_shop()
	Balatest.wait_for_input(G.STATES.SHOP)
	Balatest.q(function()
		if Balatest.internal.abort then
			return
		end
		G.FUNCS.toggle_shop()
	end)
	Balatest.wait_for_input(G.STATES.BLIND_SELECT)
end

--- Ends the round and navigates to the next one.
---@param with_blind? string|fun():string The blind to go to.
function Balatest.next_round(with_blind)
	Balatest.end_round()
	Balatest.cash_out()
	Balatest.exit_shop()
	Balatest.start_round(with_blind)
end

local suits = {
	s = "Spades",
	S = "Spades",
	h = "Hearts",
	H = "Hearts",
	c = "Clubs",
	C = "Clubs",
	d = "Diamonds",
	D = "Diamonds",
}

local ranks = {
	["2"] = "2",
	["3"] = "3",
	["4"] = "4",
	["5"] = "5",
	["6"] = "6",
	["7"] = "7",
	["8"] = "8",
	["9"] = "9",
	["10"] = "10",
	["T"] = "10",
	["t"] = "10",
	["J"] = "Jack",
	["j"] = "Jack",
	["Q"] = "Queen",
	["q"] = "Queen",
	["K"] = "King",
	["k"] = "King",
	["A"] = "Ace",
	["a"] = "Ace",
	["1"] = "Ace",
}

--- Selects the specified cards.
--- @param cards Cards the cards to select.
function Balatest.internal.select(cards)
	if Balatest.internal.abort then
		return
	end
	local used = {}
	for _, v in ipairs(cards) do
		local rank = ranks[v:sub(1, -2)]
		local suit = suits[v:sub(-1)]
		local bad = true
		for k, v in ipairs(G.hand.cards) do
			if v.base.suit == suit and v.base.value == rank then
				used[#used + 1] = table.remove(G.hand.cards, k)
				bad = false
				break
			end
		end
		if bad then
			Balatest.internal.abort = "A card (" .. v .. ") was not in hand, but it needed to be played."
		end
	end
	for k, v in ipairs(used) do
		G.hand.cards[#G.hand.cards + 1] = v
		G.hand:add_to_highlighted(v, true)
	end
	G.hand:align_cards()
end

--- @alias Cards string[]

--- Plays a hand with the specified cards in the specified order.
--- @param cards Cards|fun(): Cards The cards to play or a function to determine the cards to play.
--- @param expect_loss? boolean|number Set this to `true` if this hand should lose the run. Set it to a number to change the timeout length from the default of 3 seconds.
function Balatest.play_hand(cards, expect_loss)
	Balatest.wait_for_input(G.STATES.SELECTING_HAND)
	cards = Balatest.internal.ensure_not_nil(cards)
	Balatest.q(function()
		Balatest.internal.select(cards())
		if Balatest.internal.abort then
			return
		end
		G.FUNCS.play_cards_from_highlighted()
	end)
	if expect_loss then
		local timeout = type(expect_loss) == "boolean" and 3 or expect_loss
		local blame = debug.getinfo(2, "Sl")
		Balatest.q({
			blocking = false,
			timer = "REAL",
			trigger = "after",
			delay = timeout,
			func = function()
				Balatest.internal.abort = string.format(
					"[%s]:%d Expected the game to be lost within %d seconds",
					blame.source,
					blame.currentline,
					timeout
				)
			end,
		})
		Balatest.q(function()
			return G.STATE == G.STATES.GAME_OVER and G.STATE_COMPLETE
		end)
	else
		Balatest.wait_for_input({ G.STATES.SELECTING_HAND, G.STATES.ROUND_EVAL })
	end
end

--- Discards the specified cards.
--- @param cards Cards|fun(): Cards The cards to discard or a function to determine the cards to discard.
function Balatest.discard(cards)
	Balatest.wait_for_input(G.STATES.SELECTING_HAND)
	cards = Balatest.internal.ensure_not_nil(cards)
	Balatest.q(function()
		Balatest.internal.select(cards())
		if Balatest.internal.abort then
			return
		end
		G.FUNCS.discard_cards_from_highlighted()
	end)
	Balatest.wait_for_input(G.STATES.SELECTING_HAND)
end

--- Highlights the specified cards in the specified order.
--- @param cards Cards|fun(): Cards The cards to highlight or a function to determine the cards to highlight.
function Balatest.highlight(cards)
	Balatest.wait_for_input({ G.STATES.SELECTING_HAND, G.STATES.SMODS_BOOSTER_OPENED })
	cards = Balatest.internal.ensure_not_nil(cards)
	Balatest.q(function()
		Balatest.internal.select(cards())
	end)
	Balatest.wait_for_input({ G.STATES.SELECTING_HAND, G.STATES.SMODS_BOOSTER_OPENED })
end

--- Unhighlights all cards in hand.
function Balatest.unhighlight_all()
	Balatest.wait_for_input({ G.STATES.SELECTING_HAND, G.STATES.SMODS_BOOSTER_OPENED })
	Balatest.q(function()
		G.hand:unhighlight_all()
	end)
	Balatest.wait_for_input({ G.STATES.SELECTING_HAND, G.STATES.SMODS_BOOSTER_OPENED })
end

--- Uses a consumable.
--- @param card Card|fun(): Card The card to use or a function to determine the card to use.
function Balatest.use(card)
	Balatest.wait_for_input()
	card = Balatest.internal.ensure_not_nil(card)
	Balatest.q(function()
		G.FUNCS.use_card({ config = { ref_table = card() } })
	end)
	Balatest.wait_for_input()
end

--- Buys something from the shop.
--- @param func fun(): Card The function to determine the card to buy.
function Balatest.buy(func)
	Balatest.wait_for_input(G.STATES.SHOP)
	func = Balatest.internal.ensure_not_nil(func)
	Balatest.q(function()
		G.FUNCS.buy_from_shop({ config = { ref_table = func() } })
	end)
	Balatest.wait(1) -- Wait for ease_dollars() to finish
	Balatest.wait_for_input(G.STATES.SHOP)
end

--- Redeems a voucher from the shop.
--- @param func fun(): SMODS.Voucher The function to determine the voucher to redeem.
function Balatest.redeem(func)
	Balatest.wait_for_input(G.STATES.SHOP)
	Balatest.use(func)
	Balatest.wait_for_input(G.STATES.SHOP)
end

--- Waits until the booster pack has been fully opened.
function Balatest.internal.wait_for_booster()
	Balatest.q(function()
		return G.STATE == G.STATES.SMODS_BOOSTER_OPENED
			and G.STATE_COMPLETE
			and G.pack_cards
			and #G.pack_cards.cards > 0
			and not G.CONTROLLER.locked
			and not (G.GAME.STOP_USE and G.GAME.STOP_USE > 0)
	end)
end

--- Opens a booster from the shop.
--- @param func fun(): SMODS.Booster The function to determine the booster to open.
function Balatest.open(func)
	Balatest.wait_for_input(G.STATES.SHOP)
	Balatest.use(func)
	Balatest.internal.wait_for_booster()
end

--- Skips the currently open booster pack.
function Balatest.skip_booster()
	Balatest.internal.wait_for_booster()
	Balatest.q(function()
		G.FUNCS.skip_booster({})
	end)
	Balatest.wait_for_input(G.STATES.SHOP)
end

--- Sells something.
--- @param card Card|fun(): Card The card to sell or a function to determine the card to sell.
function Balatest.sell(card)
	Balatest.wait_for_input()
	card = Balatest.internal.ensure_not_nil(card)
	Balatest.q(function()
		G.FUNCS.sell_card({ config = { ref_table = card() } })
	end)
	Balatest.wait_for_input()
end

--- The number of hooks currently active which need to be removed.
Balatest.internal.hook_count = 0
local origs = setmetatable({}, { __mode = "k" })
--- Hooks an arbitrary value. The hook is applied in queue and is reset at the end of the test.
--- @param obj table|fun():table The object to hook.
--- @param name any The key within the object to hook.
--- @param new any The new value.
function Balatest.hook_raw(obj, name, new)
	obj = Balatest.internal.ensure_not_nil(obj)
	local cleanup = false
	Balatest.q(function()
		if Balatest.internal.abort then
			return
		end
		origs[obj()] = origs[obj()] or setmetatable({}, { __mode = "k" })
		if not origs[obj()][name] then
			origs[obj()][name] = { obj()[name] }
			Balatest.internal.hook_count = Balatest.internal.hook_count + 1
			cleanup = true
		end
		obj()[name] = new
	end)

	local test = Balatest.current_test
	Balatest.internal.tq(Event({
		no_delete = true,
		blocking = false,
		blockable = false,
		func = function()
			if not Balatest.done[test] then
				return false
			end
			if cleanup then
				obj()[name] = origs[obj()][name][1]
				origs[obj()][name] = nil
				Balatest.internal.hook_count = Balatest.internal.hook_count - 1
			end
			return true
		end,
	}))
end

--- Hooks a function. The hook is applied in queue and is reset at the end of the test.
--- @param obj table|fun():table The object to hook.
--- @param name any The key within the object to hook.
--- @param func fun(orig: function, ...):... The new function. The original function is passed as the first parameter.
function Balatest.hook(obj, name, func)
	local obj2 = Balatest.internal.ensure_not_nil(obj)
	Balatest.hook_raw(obj, name, function(...)
		return func(origs[obj2()][name][1], ...)
	end)
end

--- Reloads the game as though the player saved, quit, and continued.
function Balatest.reload()
	Balatest.wait_for_input()
	Balatest.q(function()
		G.E_MANAGER:clear_queue()
		G.E_MANAGER:add_event(Event({
			no_delete = true,
			func = function()
				save_run()
				local save = type(G.ARGS.save_run) == "table" and STR_PACK(G.ARGS.save_run) or G.ARGS.save_run
				-- save = love.data.compress('string', 'deflate', save, 1)
				-- save = love.data.decompress('string', 'deflate', save)
				if save ~= nil then
					save = STR_UNPACK(save)
				end

				G:delete_run()
				G.SAVED_GAME = save
				G:start_run({ savetext = save })
				return true
			end,
		}))
	end)
	Balatest.wait_for_input()
end

--- Waits for the standard event queue to complete.
--- @param depth? integer If set, waits additional times. This is useful to wait for an event that queues another event (etc).
function Balatest.wait(depth)
	local done = false
	Balatest.q(function()
		local function recurse(d)
			G.E_MANAGER:add_event(Event({
				func = function()
					if d == 0 then
						done = true
					else
						recurse(d - 1)
					end
					return true
				end,
			}))
		end
		recurse(depth or 0)
	end)
	Balatest.q(function()
		return done
	end)
end
