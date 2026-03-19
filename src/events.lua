G.E_MANAGER.queues.Balatest = {}
G.E_MANAGER.queues.Balatest_Run = {}

local function protect(f, t)
    return function()
        if not t and Balatest.internal.abort then return true end
        local res, ret = pcall(f)
        if not res and not Balatest.done[Balatest.current_test] then Balatest.internal.abort = ret or true end
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
        f = Event { no_delete = true, func = protect(f, t) }
    else
        error("Expected a function or event, got a " .. type(f), 3)
    end
    f.created_on_pause = true
    return f
end

--- Queues a test-level event. Works similarly to `Balatest.q()`.
--- @param f (fun():boolean?)|Event The event or a function to run turn into an event.
--- @param front boolean|nil `true` to add the event to the front of the queue, rather than the end.
function Balatest.internal.tq(f, front)
    G.E_MANAGER:add_event(protect_ev(f, true), 'Balatest', front)
end

--- Queues an event to be run during this test.
--- Note that events added this way implicitly `return true` unless you explicitly `return false`, unlike the vanilla ones.
--- @param f (fun():boolean?)|Event The event or a function to run turn into an event.
--- @param front boolean|nil `true` to add the event to the front of the queue, rather than the end.
function Balatest.q(f, front)
    G.E_MANAGER:add_event(protect_ev(f), 'Balatest_Run', front)
end

--- @alias State number A state in G.STATES
--- Queues an event to wait for manual input to be possible.
--- @param state State? If set, also waits for the game to reach this state.
--- @param front boolean? Forwarded to `Balatest.q`.
function Balatest.wait_for_input(state, front)
    Balatest.q(function()
        return abort or ((not state or G.STATE == state) and not G.CONTROLLER.locked and
            not (G.GAME.STOP_USE and G.GAME.STOP_USE > 0))
    end, front)
    Balatest.wait()
end

--- Starts the next blind from the blind select screen.
---@param with_blind? string The blind to go to.
function Balatest.start_round(with_blind)
    Balatest.q(function()
        if abort then return end
        G.FUNCS.select_blind {
            config = { ref_table = G.P_BLINDS[with_blind or Balatest.current_test_object.blind or 'bl_small'] },
            UIBox = { get_UIE_by_ID = function() end }
        }
    end)
    Balatest.wait_for_input(G.STATES.SELECTING_HAND)
    -- local done = false
    -- Balatest.q(function()
    --     if abort then return true end
    --     local count = #G.deck.cards
    --     for i = 1, count do
    --         draw_card(G.deck, G.hand, i * 100 / count, 'up', true)
    --     end
    --     G.E_MANAGER:add_event(Event { func = function()
    --         done = true
    --         return true
    --     end })
    --     return true
    -- end)
    -- Balatest.q(function()
    --     return abort or done
    -- end)
end

--- Skips the next blind for the specified tag.
--- @param for_tag string The tag ID that will spawn.
function Balatest.skip_blind(for_tag)
    Balatest.wait_for_input(G.STATES.BLIND_SELECT)
    Balatest.q(function()
        if abort then return end
        G.FUNCS.skip_blind { UIBox = { get_UIE_by_ID = function() return { config = { ref_table = Tag(for_tag) } } end } }
    end)
    Balatest.wait_for_input(G.STATES.BLIND_SELECT)
end

--- Ends the current round as though the blind was won and goes to the results screen.
function Balatest.end_round()
    Balatest.wait_for_input()
    Balatest.q(function()
        if abort then return end
        G.GAME.chips = G.GAME.blind.chips
        G.STATE = G.STATES.NEW_ROUND
        G.STATE_COMPLETE = false
    end)
    Balatest.wait_for_input(G.STATES.ROUND_EVAL)
end

--- Cashes out from the results screen and goes to the shop.
function Balatest.cash_out()
    Balatest.q(function()
        if abort then return end
        G.FUNCS.cash_out { config = {} }
    end)
    Balatest.wait_for_input()
end

--- Exits the shop and goes to the blind select screen.
function Balatest.exit_shop()
    Balatest.q(function()
        if abort then return end
        G.FUNCS.toggle_shop()
    end)
    Balatest.wait_for_input(G.STATES.BLIND_SELECT)
end

--- Ends the round and navigates to the next one.
---@param with_blind? string The blind to go to.
function Balatest.next_round(with_blind)
    Balatest.end_round()
    Balatest.cash_out()
    Balatest.exit_shop()
    Balatest.start_round(with_blind)
end

local suits = {
    s = 'Spades',
    S = 'Spades',
    h = 'Hearts',
    H = 'Hearts',
    c = 'Clubs',
    C = 'Clubs',
    d = 'Diamonds',
    D = 'Diamonds',
}

local ranks = {
    ['2'] = '2',
    ['3'] = '3',
    ['4'] = '4',
    ['5'] = '5',
    ['6'] = '6',
    ['7'] = '7',
    ['8'] = '8',
    ['9'] = '9',
    ['10'] = '10',
    ['T'] = '10',
    ['t'] = '10',
    ['J'] = 'Jack',
    ['j'] = 'Jack',
    ['Q'] = 'Queen',
    ['q'] = 'Queen',
    ['K'] = 'King',
    ['k'] = 'King',
    ['A'] = 'Ace',
    ['a'] = 'Ace',
    ['1'] = 'Ace',
}

local function select(cards)
    if abort then return end
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
            abort = 'A card (' .. v .. ') was not in hand, but it needed to be played.'
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
--- @param cards Cards
--- @param expect_loss? boolean|number Set this to `true` if this hand should lose the run. Set it to a number to change the timeout length from the default of 2 seconds.
function Balatest.play_hand(cards, expect_loss)
    Balatest.q(function()
        select(cards)
        if abort then return end
        G.FUNCS.play_cards_from_highlighted()
    end)
    if expect_loss then
        local timeout = type(expect_loss) == "boolean" and 2 or expect_loss
        local blame = debug.getinfo(2, "Sl")
        Balatest.q {
            blocking = false,
            timer = 'REAL',
            trigger = 'after',
            delay = timeout,
            func = function()
                abort = string.format(
                    '[%s]:%d Expected the game to be lost within %d seconds',
                    blame.source, blame.currentline, timeout)
            end
        }
        Balatest.q(function()
            return G.STATE == G.STATES.GAME_OVER and G.STATE_COMPLETE
        end)
    else
        Balatest.wait_for_input()
    end
end

--- Discards the specified cards.
--- @param cards Cards
function Balatest.discard(cards)
    Balatest.q(function()
        select(cards)
        if abort then return end
        G.FUNCS.discard_cards_from_highlighted()
    end)
    Balatest.wait_for_input(G.STATES.SELECTING_HAND)
end

--- Highlights the specified cards in the specified order.
--- @param cards Cards
function Balatest.highlight(cards)
    Balatest.q(function()
        select(cards)
    end)
    Balatest.wait_for_input()
end

--- Unhighlights all cards in hand.
function Balatest.unhighlight_all()
    Balatest.q(function()
        G.hand:unhighlight_all()
    end)
    Balatest.wait_for_input()
end

--- Uses a consumable.
--- @param card Card|fun(): Card The card to use or a function to determine the card to use.
--- @param instant nil Deprecated.
function Balatest.use(card, instant)
    if instant then
        if instant ~= 1 then
            sendWarnMessage(
                'Instant mode on Balatest.use can cause unintuitive behavior; you likely want to pass a function instead. Suppress this warning by setting instant to 1.',
                'Balatest')
        end
        G.FUNCS.use_card { config = { ref_table = card } }
    else
        Balatest.q(function()
            G.FUNCS.use_card { config = { ref_table = type(card) == 'function' and card() or card } }
        end)
    end
    Balatest.wait_for_input(nil, instant)
end

--- Buys something from the shop.
--- @param func fun(): Card The function to determine the card to buy.
function Balatest.buy(func)
    Balatest.q(function()
        G.FUNCS.buy_from_shop { config = { ref_table = func() } }
    end)
    Balatest.wait_for_input()
end

--- Redeems a voucher from the shop.
--- @param func fun(): Voucher The function to determine the voucher to redeem.
function Balatest.redeem(func)
    Balatest.q(function()
        func():redeem()
    end)
    Balatest.wait_for_input()
end

--- Opens a booster from the shop.
--- @param func fun(): Booster The function to determine the booster to open.
function Balatest.open(func)
    Balatest.q(function()
        func():open()
    end)
    Balatest.wait_for_input()
end

--- Sells something.
--- @param card Card|fun(): Card The card to sell or a function to determine the card to sell.
function Balatest.sell(card)
    Balatest.q(function()
        (type(card) == 'function' and card() or card):sell_card()
    end)
    Balatest.wait_for_input()
end

--- The number of hooks currently active which need to be removed.
Balatest.internal.hook_count = 0
local hooks = setmetatable({}, { __mode = 'k' })
--- Hooks an arbitrary value. The hook is applied in queue and is reset at the end of the test.
--- @param obj table The object to hook.
--- @param name any The key withing the object to hook.
--- @param new any The new value.
function Balatest.hook_raw(obj, name, new)
    local prev = obj[name]
    Balatest.q(function()
        if abort then return end
        obj[name] = new
    end)

    hooks[obj] = hooks[obj] or {}
    local cleanup = not hooks[obj][name]
    if cleanup then
        Balatest.internal.hook_count = Balatest.internal.hook_count + 1
        hooks[obj][name] = true
        local test = Balatest.current_test
        Balatest.internal.tq(Event {
            no_delete = true,
            blocking = false,
            blockable = false,
            func = function()
                if not Balatest.done[test] then return false end
                obj[name] = prev
                hooks[obj][name] = nil
                Balatest.internal.hook_count = Balatest.internal.hook_count - 1
                return true
            end
        })
    end
end

--- Hooks an function. The hook is applied in queue and is reset at the end of the test.
--- @param obj table The object to hook.
--- @param name any The key withing the object to hook.
--- @param func fun(orig: function, ...) The new function. The original function is passed as the first parameter.
function Balatest.hook(obj, name, func)
    local prev = obj[name]
    Balatest.hook_raw(obj, name, function(...)
        return func(prev, ...)
    end)
end

--- Reloads the game as though the player saved, quit, and continued.
function Balatest.reload()
    Balatest.q(function()
        G.E_MANAGER:clear_queue()
        G.E_MANAGER:add_event(Event {
            no_delete = true,
            func = function()
                save_run()
                local save = type(G.ARGS.save_run) == 'table' and STR_PACK(G.ARGS.save_run) or G.ARGS.save_run
                -- save = love.data.compress('string', 'deflate', save, 1)
                -- save = love.data.decompress('string', 'deflate', save)
                if save ~= nil then save = STR_UNPACK(save) end

                G:delete_run()
                G.SAVED_GAME = save
                G:start_run { savetext = save }
                return true
            end
        })
    end)
    Balatest.wait_for_input()
end

--- Waits for the standard event queue to complete.
--- @param depth? integer If set, waits additional times. This is useful to wait for an event that queues another event (etc).
function Balatest.wait(depth)
    local done = false
    Balatest.q(function()
        local function recurse(d)
            G.E_MANAGER:add_event(Event {
                func = function()
                    if d == 0 then
                        done = true
                    else
                        recurse(d - 1)
                    end
                    return true
                end
            })
        end
        recurse(depth or 0)
    end)
    Balatest.q(function() return done end)
end
