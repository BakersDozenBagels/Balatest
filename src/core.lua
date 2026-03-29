Balatest = {}
--- Used internally by Balatest to manage state. Don't touch this.
Balatest.internal = {}

assert(SMODS.load_file 'src/testplay.lua')()
assert(SMODS.load_file 'src/events.lua')()
assert(SMODS.load_file 'src/assertions.lua')()
assert(SMODS.load_file 'src/cli.lua')()

--- @alias Result {success:true}|{success:false,reason:string?}|{skipped:true,reason:string}

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
Balatest.internal.done_count = 0
--- The ID for the current test, or `nil` if no test is being run.
--- @type string|nil
Balatest.current_test = nil
--- The configuration for the current test, or `nil` if no test is being run.
--- @type TestPlay|nil
Balatest.current_test_object = nil

SMODS.Challenges = SMODS.Challenges or {}
SMODS.Challenges.Balatest_Test_Runner = SMODS.Challenges.Balatest_Test_Runner or { calculate = function() end }

---@type string|true? The reason why the current test should fail.
Balatest.internal.abort = nil
---@type string? The reason why the use `Balatest.kill()`ed this test.
Balatest.internal.kill = nil

--- Runs a suite of tests. If no parameters are given, runs every registered test.
--- @param mod? string The mod to run tests from.
--- @param category? string The category to run tests from.
--- @param after? fun(test_name: string, result: Result) The result handler for these tests. If unset, defaults to a simple logger.
function Balatest.run_tests(mod, category, after)
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

    Balatest.internal.done_count = 0
    local prev_speed = G.SETTINGS.GAMESPEED
    G.SETTINGS.GAMESPEED = 65536
    sendInfoMessage(
        'Running ' .. #todo .. ' tests...' .. (skip_count ~= 0 and (' (' .. skip_count .. ' skipped)') or ''),
        'Balatest')
    for _, v in ipairs(todo) do
        Balatest.run_test(Balatest.tests[v], after)
    end
    Balatest.internal.tq(Event {
        blocking = false,
        no_delete = true,
        func = function()
            if Balatest.internal.done_count ~= #todo then return false end

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
            sendInfoMessage(Balatest.internal.done_count .. ' tests ran.', 'Balatest')
            sendInfoMessage(
                pass ..
                ' succeeded, ' .. fail .. ' failed' .. (skip_count == 0 and '.' or (', ' .. skip_count .. ' skipped.')),
                'Balatest')
            G.SETTINGS.GAMESPEED = prev_speed
            return true
        end
    })
end

--- The default logger for test results. 
---@param name string The test's name.
---@param res Result The rest's results.
local function log_result(name, res)
    if res.skipped then
        sendWarnMessage('Test ' .. name .. ' skipped: ' .. res.reason, 'Balatest')
    elseif res.success then
        sendInfoMessage('Test ' .. name .. ' passed.', 'Balatest')
    else
        sendErrorMessage('Test ' .. name .. ' failed with: ' .. res.reason, 'Balatest')
    end
end

--- Runs a single test.
--- @param test string|TestPlay The test to run.
--- @param after? fun(test_name: string, result: Result) The result handler for this test. If unset, defaults to a simple logger.
function Balatest.run_test(test, after)
    if type(test) == 'string' then test = Balatest.tests[test] end
    if test == nil then
        sendWarnMessage('That test does not exist.', 'Balatest')
        return
    end
    if not test.name then test.name = 'temporary' end

    Balatest.internal.tq(function()
        Balatest.done[test.name] = nil
        Balatest.internal.abort = nil
        Balatest.current_test = test.name
        Balatest.current_test_object = test

        if Balatest.internal.kill then
            Balatest.internal.abort = Balatest.internal.kill
        end
    end)

    test:run_test()

    Balatest.internal.tq(function()
        if Balatest.internal.kill and not Balatest.done[test.name] then
            Balatest.done[test.name] = { skipped = true, reason = Balatest.internal.kill }
            Balatest.internal.done_count = Balatest.internal.done_count + 1
        elseif Balatest.internal.abort and not Balatest.done[test.name] then
            Balatest.done[test.name] = { success = false, reason = type(Balatest.internal.abort) == 'string' and
            Balatest.internal.abort or 'Aborted' }
            Balatest.internal.done_count = Balatest.internal.done_count + 1
        elseif not Balatest.done[test.name] then
            Balatest.done[test.name] = { success = false, reason = 'Unknown' }
            Balatest.internal.done_count = Balatest.internal.done_count + 1
        end
        (after or log_result)(test.name, Balatest.done[test.name])
        Balatest.current_test = nil
        Balatest.current_test_object = nil
    end)
    Balatest.internal.tq(function()
        return Balatest.internal.hook_count == 0
    end)
    Balatest.internal.tq(function()
        G.E_MANAGER.queues.Balatest_Run = {}
    end)
end

--- Stops the current test batch.
function Balatest.kill()
    Balatest.internal.kill = "Tests were killed"
    Balatest.internal.abort = Balatest.internal.kill
    Balatest.internal.tq(function()
        Balatest.internal.kill = nil
    end)
end
