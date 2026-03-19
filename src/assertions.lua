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
