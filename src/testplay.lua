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
--- @field required_mods? string[]|string The test will be skipped if any of these mods are not loaded.
--- @field skip? fun(): boolean|string? Return `true` or any string to skip this test.
--- @field execute? fun() The function to perform the actions under test.
--- @field assert? fun() The function to assert conditions about the game state.
--- @field run_test? fun(TestPlay) The function to run the test. Normally, this is generated for you.

--- Registers a test.
--- @param settings TestPlay The test to register.
function Balatest.TestPlay(settings)
    local mod = SMODS.current_mod and SMODS.current_mod.id or ''
    settings.name = ((SMODS.current_mod and mod .. '_') or '') ..
        (settings.name or ('unnamed_' .. (#Balatest.tests + 1)))
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
    settings.run_test = settings.run_test or Balatest.internal.run_test_play
    return settings
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

--- Runs a TestPlay.
---@param self TestPlay
function Balatest.internal.run_test_play(self)
    local test_done = false
    Balatest.internal.tq(function()
        if Balatest.internal.abort then
            return
        end

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
            deck = { name = self.back or 'Red Deck' },
            stake = self.stake,
            seed = self.seed,
            challenge = {
                id = 'Balatest_Test_Runner',
                jokers = fix_jokers(self.jokers or {}),
                consumeables = fix_jokers(self.consumeables or {}),
                vouchers = fix_jokers(self.vouchers or {}),
                rules = {
                    modifiers = {
                        { id = 'dollars',   value = self.dollars or 0 },
                        { id = 'discards',  value = self.discards or 999 },
                        { id = 'hands',     value = self.hands or 999 },
                        { id = 'hand_size', value = self.hand_size or 52 },
                        unpack(self.modifiers or {})
                    },
                    custom = {
                        { id = 'no_reward' },
                        { id = 'no_interest' },
                        { id = 'no_extra_hand_money' },
                        { id = 'money_per_discard',  value = 0 },
                        unpack(self.custom_rules or {})
                    }
                },
                deck = self.deck
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
        Balatest.wait_for_input(G.STATES.BLIND_SELECT)
        if not self.no_auto_start then
            Balatest.start_round()
        end

        Balatest.q(function()
            local r, e = pcall(self.execute or function() end)
            if not r and not Balatest.done[self.name] then Balatest.internal.abort = e or true end
        end)

        Balatest.q(function()
            Balatest.wait()
            Balatest.q(function()
                if not Balatest.done[self.name] then
                    local r, e = pcall(self.assert or function() end)
                    if not r then
                        Balatest.done[self.name] = { success = false, reason = e }
                    else
                        Balatest.done[self.name] = { success = true }
                    end
                    Balatest.internal.done_count = Balatest.internal.done_count + 1
                end
                test_done = true
            end)
        end)
    end)
    Balatest.internal.tq(function()
        return Balatest.internal.abort or test_done
    end)
end
