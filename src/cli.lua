-- Give mods 5 frames for load-order shenanigans
local done = false
Balatest.internal.tq(function()
    local function recurse(d)
        G.E_MANAGER:add_event(Event {
            no_delete = true,
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
    recurse(5)
end)
Balatest.internal.tq(function() return done end)

-- Arguments use colons because Lovely complains about equals
function parse_args()
    local run = 0
    local mod = nil
    local category = nil
    for _, v in ipairs(arg) do
        print(v)
        if v == "--balatest-run-tests" then
            if run ~= 0 and run ~= 1 then
                error("Invalid Balatest CLI arguments")
            end
            run = 1
        elseif v:sub(1, 21) == "--balatest-run-tests:" then
            if run ~= 0 and run ~= 1 then
                error("Invalid Balatest CLI arguments")
            end
            run = 1
            mod = v:sub(22)
        elseif v:sub(1, 20) == "--balatest-category:" then
            if run ~= 0 and run ~= 1 then
                error("Invalid Balatest CLI arguments")
            end
            run = 1
            category = v:sub(21)
        elseif v:sub(1, 20) == "--balatest-run-test:" then
            if run ~= 0 and run ~= 2 then
                error("Invalid Balatest CLI arguments")
            end
            run = 2
            mod = v:sub(21)
        end
    end

    return run, mod, category
end

-- Don't tq this so `error()`s will crash
G.E_MANAGER:add_event(Event {
    no_delete = true,
    func = function()
        local raw_love_errorhandler = love.errorhandler
        function love.errorhandler(msg)
            -- No return to exit immediately
            raw_love_errorhandler(msg)
        end

        local run, mod, category = parse_args()

        if run ~= 1 and run ~= 2 then
            love.errorhandler = raw_love_errorhandler
            return
        end

        if run == 1 then
            if category and not mod then
                error("Invalid Balatest CLI arguments")
            end
            Balatest.run_tests(mod, category)
        elseif run == 2 then
            Balatest.run_test(mod)
        end

        Balatest.internal.tq(function()
            local fail = 0
            for _, v in pairs(Balatest.done) do
                if not v.skipped and not v.success then
                    fail = fail + 1
                end
            end
            love.event.quit(fail)
        end)

        return true
    end
}, 'Balatest')
