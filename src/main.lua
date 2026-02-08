Balatest = {}

--- @class TestPlay The configuration for one unit test.
--- @field name string The unique name for this test.
--- @field category? string[]|string The categories this test is a part of. This is used to run a subset of tests.
--- @field back? string The deck to use. Defaults to `'Red Deck'`.
--- @field stake? integer|string The stake to use. Defaults to `1`.
--- @field seed? string The seed to use. Use `nil` for a random seed.
--- @field jokers? string[] The jokers to start with.
--- @field consumeables? string[] The consumables to start with.
--- @field vouchers? string[] The vouchers to start with.
--- @field dollars? integer The amount of money to start with. Defaults to `0`.
--- @field discards? integer The amount of discards to start with. Defaults to `999`.
--- @field hands? integer The amount of hands to start with. Defaults to `999`.
--- @field hand_size? integer The amount of hand size to start with. Defaults to `999`.
--- @field modifiers? {id:string,value?:any}[] The challenge modifiers to set. Corresponds to `challenge.rules.modifiers`.
--- @field custom? {id:string,value?:any}[] The challenge rules to set. Corresponds to `challenge.rules.custom`. By default, `'no_reward'`, `'no_interest'`, `'no_extra_hand_money'`, and `'money_per_discard' = 0` are set.
--- @field deck? table|{type?:string|"Challenge Deck",cards?:table[],yes_ranks?:table<string,true>,yes_suits?:table<string,true>,no_ranks?:table<string,true>,no_suits?:table<string,true>,enhancement?:string,edition?:string,seal?:string} The starting deck of cards. Corresponds to `challenge.deck`.
--- @field blind? string The only blind which will spawn for this test. Defaults to `'bl_small'`.
--- @field no_auto_start? boolean Set this to true to skip automatically entering the first blind.
--- @field requires nil Deprecated.
--- @field required_mods? string[]|string The test will be skipped if any of these mods are not loaded.
--- @field skip? fun(): boolean? Return `true` or any string to skip this test.
--- @field execute? fun() The function to perform the actions under test.
--- @field assert? fun() The function to assert conditions about the game state.

--- @alias Result {success:true}|{success:false,reason:string}|{skipped:true,reason:string}

--- Every test registered with `Balatest.TestPlay`.
--- @type TestPlay[]
Balatest.tests = {}
--- Every test registered with `Balatest.TestPlay`, sorted by mod ID.
--- @type {[string]:{[string]:boolean}}
Balatest.tests_by_mod = {}
--- Every test registered with `Balatest.TestPlay`, sorted by mod ID, then by category.
--- @type {[string]:{[string]:{[string]:boolean}}}
Balatest.tests_by_mod_and_category = {}
--- Test IDs, in the order in which the corresponding tests are run. By default, this is exactly the order tests are registered in.
--- @type string[]
Balatest.test_order = {}
--- Contains information on the status of previously run tests.
--- @type {[string]:Result}
Balatest.done = {}
--- How many of the tests in the current batch have completed running.
Balatest.done_count = 0
--- The ID for the current test, or `nil` if no test is being run.
--- @type string|nil
Balatest.current_test = nil
--- The configuration for the current test, or `nil` if no test is being run.
--- @type TestPlay|nil
Balatest.current_test_object = nil
--- The number of hooks currently active which need to be removed.
Balatest.hook_count = 0

SMODS.Challenges = SMODS.Challenges or {}
SMODS.Challenges.Balatest_Test_Runner = SMODS.Challenges.Balatest_Test_Runner or { calculate = function() end }

G.E_MANAGER.queues.Balatest = {}
G.E_MANAGER.queues.Balatest_Run = {}
local abort, kill
local function protect(f, t)
    return function()
        if not t and abort then return true end
        local res, ret = pcall(f)
        if not res and not Balatest.done[Balatest.current_test] then abort = ret or true end
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
    return f
end
local function tq(f, front)
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
local function wait_for_input(state, front)
    Balatest.q(function()
        return abort or ((not state or G.STATE == state) and not G.CONTROLLER.locked and
            not (G.GAME.STOP_USE and G.GAME.STOP_USE > 0))
    end, front)
    Balatest.wait()
end
Balatest.wait_for_input = wait_for_input

--- Registers a test.
--- @param settings TestPlay The test to register.
function Balatest.TestPlay(settings)
    local mod = SMODS.current_mod and SMODS.current_mod.id or ''
    settings.name = ((SMODS.current_mod and mod .. '_') or '') ..
        (settings.name or ('unnamed_' .. (#Balatest.tests + 1)))
    if settings.requires then
        local req = {}
        for k, v in pairs(settings.requires or {}) do
            req[k] = (SMODS.current_mod and mod .. '_' or '') .. v
        end
        settings.requires = req
    end
    settings.category = settings.category or {}
    if type(settings.category) == "string" then settings.category = { settings.category } end
    if settings.consumables then
        settings.consumeables = settings.consumables
    elseif settings.consumeables then
        settings.consumables = settings.consumeables
    end
    Balatest.tests[settings.name] = settings
    Balatest.tests_by_mod[mod] = Balatest.tests_by_mod[mod] or {}
    Balatest.tests_by_mod[mod][settings.name] = true
    Balatest.tests_by_mod_and_category[mod] = Balatest.tests_by_mod_and_category[mod] or {}
    for _, cat in pairs(settings.category) do
        Balatest.tests_by_mod_and_category[mod][cat] = Balatest.tests_by_mod_and_category[mod][cat] or {}
        Balatest.tests_by_mod_and_category[mod][cat][settings.name] = true
    end
    Balatest.test_order[#Balatest.test_order + 1] = settings.name
end

--- Tests whether a test should be skipped.
--- @param t string The test to consider.
--- @return string? `nil`, or the reason why this test should be skipped.
function Balatest.should_skip(t)
    local test = Balatest.tests[t]
    if test.skip then
        local r = test.skip()
        if r then
            return type(r) == "boolean" and "The user-defined skip function" or r
        end
    end
    for _, m in pairs(type(test.required_mods) == "string" and { test.required_mods } or test.required_mods or {}) do
        if not next(SMODS.find_mod(m)) then
            return "Required mod " .. m .. " was not loaded."
        end
    end
end

--- Runs a suite of tests. If no parameters are given, runs every registered test.
--- @param mod? string The mod to run tests from.
--- @param category? string The category to run tests from.
function Balatest.run_tests(mod, category)
    local todo = {}
    local allowed = nil
    if category then
        if not mod then
            sendErrorMessage('No mod provided for categories. Aborting.', 'Balatest')
            return
        end
        if not Balatest.tests_by_mod_and_category[mod] then
            sendErrorMessage('That mod appears to not exist. Aborting. (Are you using your prefix instead of your ID?)',
                'Balatest')
            return
        end
        if not Balatest.tests_by_mod_and_category[mod][category] then
            sendErrorMessage('That category appears to not exist in that mod. Aborting.', 'Balatest')
            return
        end
        allowed = Balatest.tests_by_mod_and_category[mod][category]
    elseif mod then
        if not Balatest.tests_by_mod[mod] then
            sendErrorMessage('That mod appears to not exist. Aborting. (Are you using your prefix instead of your ID?)',
                'Balatest')
            return
        end
        allowed = Balatest.tests_by_mod[mod]
    end

    if not allowed then
        todo = Balatest.test_order
    else
        for _, v in ipairs(Balatest.test_order) do
            if allowed[v] then todo[#todo + 1] = v end
        end
    end

    local skip_count = 0
    local real_todo = {}
    for _, v in ipairs(todo) do
        local should_skip = Balatest.should_skip(v)
        if should_skip then
            skip_count = skip_count + 1
            Balatest.done[Balatest.tests[v].name] = { skipped = true, reason = should_skip }
        else
            real_todo[#real_todo + 1] = v
        end
    end
    todo = real_todo

    Balatest.done_count = 0
    local prev_speed = G.SETTINGS.GAMESPEED
    G.SETTINGS.GAMESPEED = 65536
    sendInfoMessage(
        'Running ' .. #todo .. ' tests...' .. (skip_count ~= 0 and (' (' .. skip_count .. ' skipped)') or ''),
        'Balatest')
    for _, v in ipairs(todo) do
        Balatest.run_test(Balatest.tests[v])
    end
    tq(Event {
        blocking = false,
        no_delete = true,
        func = function()
            if Balatest.done_count ~= #todo then return false end

            local pass, fail = 0, 0
            skip_count = 0
            for _, v in pairs(Balatest.done) do
                if v.skipped then
                    skip_count = skip_count + 1
                elseif v.success then
                    pass = pass + 1
                else
                    fail = fail + 1
                end
            end
            sendInfoMessage(Balatest.done_count .. ' tests ran.', 'Balatest')
            sendInfoMessage(
                pass ..
                ' succeeded, ' .. fail .. ' failed' .. (skip_count == 0 and '.' or (', ' .. skip_count .. ' skipped.')),
                'Balatest')
            G.SETTINGS.GAMESPEED = prev_speed
            return true
        end
    })
end

--- Runs a single test.
--- @param test string|TestPlay The test to run.
--- @param after? fun(test_name: string, result: Result) The result handler for this test. If unset, defaults to a simple logger.
--- @param count nil Deprecated.
function Balatest.run_test(test, after, count)
    if type(test) == 'string' then test = Balatest.tests[test] end
    if test == nil then
        sendWarnMessage('That test does not exist.', 'Balatest')
        return
    end
    if not test.name then test.name = 'temporary' end
    Balatest.done[test.name] = nil
    local test_done = false
    local pre_fail = false
    tq(function()
        if kill then
            abort = kill
            return
        end
        abort = nil
        if test.requires then
            sendWarnMessage('requires (on test ' .. test.name ..
                ') is deprecated and will be removed in a future release.', 'Balatest')
        end
        for _, v in pairs(test.requires or {}) do
            if not Balatest.done[v] then
                pre_fail = true
                break
            end
            if not Balatest.done[v].success then
                abort = 'Required test ' .. v .. ' failed'
                return
            end
        end
        if pre_fail then
            if count == Balatest.done_count then
                abort = 'Tests stalled'
            else
                Balatest.run_test(test, after, Balatest.done_count)
            end
            return
        end

        Balatest.done[test.name] = nil
        Balatest.current_test = test.name
        Balatest.current_test_object = test

        local function fix_jokers(j)
            local res = {}
            for k, v in ipairs(j) do
                if type(v) == 'string' then
                    res[k] = { id = v }
                else
                    res[k] = v
                end
            end
            return res
        end

        local args = {
            deck = { name = test.back or 'Red Deck' },
            stake = test.stake,
            seed = test.seed,
            challenge = {
                id = 'Balatest_Test_Runner',
                jokers = fix_jokers(test.jokers or {}),
                consumeables = fix_jokers(test.consumeables or {}),
                vouchers = fix_jokers(test.vouchers or {}),
                rules = {
                    modifiers = {
                        { id = 'dollars',   value = test.dollars or 0 },
                        { id = 'discards',  value = test.discards or 999 },
                        { id = 'hands',     value = test.hands or 999 },
                        { id = 'hand_size', value = test.hand_size or 52 },
                        unpack(test.modifiers or {})
                    },
                    custom = {
                        { id = 'no_reward' },
                        { id = 'no_interest' },
                        { id = 'no_extra_hand_money' },
                        { id = 'money_per_discard',  value = 0 },
                        unpack(test.custom_rules or {})
                    }
                },
                deck = test.deck
            }
        }

        G.SETTINGS.paused = true
        G.GAME.viewed_back = nil
        G.E_MANAGER:clear_queue()
        G.E_MANAGER:add_event(Event {
            no_delete = true,
            func = function()
                G:delete_run()
                return true
            end
        })
        G.E_MANAGER:add_event(Event {
            no_delete = true,
            func = function()
                -- No idea why this needs to be here.
                G.TAROT_INTERRUPT = nil
                G:start_run(args)
                return true
            end
        })
        wait_for_input(G.STATES.BLIND_SELECT)
        if not test.no_auto_start then
            Balatest.start_round()
        end

        Balatest.q(function()
            local r, e = pcall(test.execute or function() end)
            if not r and not Balatest.done[test.name] then abort = e or true end
        end)

        Balatest.q(function()
            if abort then return end
            Balatest.wait()
            Balatest.q(function()
                if abort then return end
                if not Balatest.done[test.name] then
                    local r, e = pcall(test.assert or function() end)
                    if not r then
                        Balatest.done[test.name] = { success = false, reason = e }
                        Balatest.done_count = Balatest.done_count + 1
                    else
                        Balatest.done[test.name] = { success = true }
                        Balatest.done_count = Balatest.done_count + 1
                    end
                end
                test_done = true
            end)
        end)
    end)
    tq(function()
        return abort or test_done or pre_fail
    end)
    tq(function()
        if pre_fail and not abort then return end
        if kill and not Balatest.done[test.name] then
            Balatest.done[test.name] = { skipped = true, reason = kill }
            Balatest.done_count = Balatest.done_count + 1
        elseif abort and not Balatest.done[test.name] then
            Balatest.done[test.name] = { success = false, reason = type(abort) == 'string' and abort or 'Aborted' }
            Balatest.done_count = Balatest.done_count + 1
        elseif not Balatest.done[test.name] then
            Balatest.done[test.name] = { success = false, reason = 'Unknown' }
            Balatest.done_count = Balatest.done_count + 1
        end
        if after then
            after(test.name, Balatest.done[test.name])
        else
            if Balatest.done[test.name].skipped then
                sendWarnMessage('Test ' .. test.name .. ' skipped: ' .. Balatest.done[test.name].reason, 'Balatest')
            elseif Balatest.done[test.name].success then
                sendInfoMessage('Test ' .. test.name .. ' passed.', 'Balatest')
            else
                sendErrorMessage('Test ' .. test.name .. ' failed with: ' .. Balatest.done[test.name].reason, 'Balatest')
            end
        end
        Balatest.current_test = nil
        Balatest.current_test_object = nil
    end)
    tq(function()
        return Balatest.hook_count == 0
    end)
    tq(function()
        G.E_MANAGER.queues.Balatest_Run = {}
    end)
end

--- Stops the current test batch.
function Balatest.kill()
    kill = "Tests were killed"
    abort = kill
    tq(function()
        kill = nil
    end)
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
    wait_for_input(G.STATES.SELECTING_HAND)
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
    wait_for_input(G.STATES.BLIND_SELECT)
    Balatest.q(function()
        if abort then return end
        G.FUNCS.skip_blind { UIBox = { get_UIE_by_ID = function() return { config = { ref_table = Tag(for_tag) } } end } }
    end)
    wait_for_input(G.STATES.BLIND_SELECT)
end

--- Ends the current round as though the blind was won and goes to the results screen.
function Balatest.end_round()
    wait_for_input()
    Balatest.q(function()
        if abort then return end
        G.GAME.chips = G.GAME.blind.chips
        G.STATE = G.STATES.NEW_ROUND
        G.STATE_COMPLETE = false
    end)
    wait_for_input(G.STATES.ROUND_EVAL)
end

--- Cashes out from the results screen and goes to the shop.
function Balatest.cash_out()
    Balatest.q(function()
        if abort then return end
        G.FUNCS.cash_out { config = {} }
    end)
    wait_for_input()
end

--- Exits the shop and goes to the blind select screen.
function Balatest.exit_shop()
    Balatest.q(function()
        if abort then return end
        G.FUNCS.toggle_shop()
    end)
    wait_for_input(G.STATES.BLIND_SELECT)
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
--- @param expect_loss boolean Set this to `true` if this hand should lose the run.
function Balatest.play_hand(cards, expect_loss)
    Balatest.q(function()
        select(cards)
        if abort then return end
        G.FUNCS.play_cards_from_highlighted()
    end)
    if expect_loss then
        Balatest.wait()
    else
        wait_for_input()
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
    wait_for_input(G.STATES.SELECTING_HAND)
end

--- Highlights the specified cards in the specified order.
--- @param cards Cards
function Balatest.highlight(cards)
    Balatest.q(function()
        select(cards)
    end)
    wait_for_input()
end

--- Unhighlights all cards in hand.
function Balatest.unhighlight_all()
    Balatest.q(function()
        G.hand:unhighlight_all()
    end)
    wait_for_input()
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
    wait_for_input(nil, instant)
end

--- Buys something from the shop.
--- @param func fun(): Card The function to determine the card to buy.
function Balatest.buy(func)
    Balatest.q(function()
        G.FUNCS.buy_from_shop { config = { ref_table = func() } }
    end)
    wait_for_input()
end

--- Redeems a voucher from the shop.
--- @param func fun(): Voucher The function to determine the voucher to redeem.
function Balatest.redeem(func)
    Balatest.q(function()
        func():redeem()
    end)
    wait_for_input()
end

--- Opens a booster from the shop.
--- @param func fun(): Booster The function to determine the booster to open.
function Balatest.open(func)
    Balatest.q(function()
        func():open()
    end)
    wait_for_input()
end

--- Sells something.
--- @param card Card|fun(): Card The card to sell or a function to determine the card to sell.
function Balatest.sell(card)
    Balatest.q(function()
        (type(card) == 'function' and card() or card):sell_card()
    end)
    wait_for_input()
end

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
        Balatest.hook_count = Balatest.hook_count + 1
        hooks[obj][name] = true
        local test = Balatest.current_test
        tq(Event {
            no_delete = true,
            blocking = false,
            blockable = false,
            func = function()
                if not Balatest.done[test] then return false end
                obj[name] = prev
                hooks[obj][name] = nil
                Balatest.hook_count = Balatest.hook_count - 1
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
    wait_for_input()
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

--- Asserts a condition.
--- @param bool boolean The condition to assert.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert(bool, message, level)
    if not bool then error(message or 'An assertion failed!', level or 2) end
end

--- Asserts that two numbers are equal. Handles Talisman jank for you.
--- @param a number The tested value.
--- @param b number The expected value.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert_eq(a, b, message, level)
    if to_big then
        Balatest.assert(((a == nil) == (b == nil)) and to_big(a) == to_big(b),
            message or ('Expected ' .. tostring(a) .. ' to equal ' .. tostring(b)),
            (level or 2) + 1)
    else
        Balatest.assert(a == b, message or ('Expected ' .. tostring(a) .. ' to equal ' .. tostring(b)), (level or 2) + 1)
    end
end

--- Asserts that two numbers are unequal. Handles Talisman jank for you.
--- @param a number The tested value.
--- @param b number The expected value.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert_neq(a, b, message, level)
    if to_big then
        Balatest.assert(((a == nil) == (b == nil)) and to_big(a) ~= to_big(b),
            message or ('Expected ' .. tostring(a) .. ' to differ from ' .. tostring(b)),
            (level or 2) + 1)
    else
        Balatest.assert(a ~= b, message or ('Expected ' .. tostring(a) .. ' to differ from ' .. tostring(b)),
            (level or 2) + 1)
    end
end

--- Asserts the amount of total round chips.
--- @param val number The tested value.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert_chips(val, message, level)
    Balatest.assert_eq(G.GAME.chips, val,
        message or ('Expected ' .. tostring(val) .. ' total round chips, got ' .. tostring(G.GAME.chips)),
        (level or 2) + 1)
end

--- Asserts the amount of dollars.
--- @param val number The tested value.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert_dollars(val, message, level)
    Balatest.assert_eq(G.GAME.dollars, val,
        message or ('Expected $' .. tostring(val) .. ' total, got ' .. tostring(G.GAME.dollars)),
        (level or 2) + 1)
end
