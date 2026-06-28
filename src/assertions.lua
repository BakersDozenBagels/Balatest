--- Asserts a condition.
--- @param bool boolean The condition to assert.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert(bool, message, level)
	if not bool then
		error(message or "An assertion failed!", level or 2)
	end
end

--- Asserts that two numbers are equal. Handles Talisman jank for you.
--- @param a any The tested value.
--- @param b any The expected value.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert_eq(a, b, message, level)
	if
		to_big
		and (
			(type(a) ~= "number" and (type(a) ~= "table" or not a.to_number))
			or (type(b) ~= "number" and (type(a) ~= "table" or not b.to_number))
		)
	then
		Balatest.assert(
			((a == nil) == (b == nil)) and to_big(a) == to_big(b),
			message or ("Expected " .. tostring(a) .. " to equal " .. tostring(b)),
			(level or 2) + 1
		)
	else
		Balatest.assert(
			a == b,
			message or ("Expected " .. tostring(a) .. " to equal " .. tostring(b)),
			(level or 2) + 1
		)
	end
end

--- Asserts that two numbers are within a provided tolerance of each other. Handles Talisman jank for you.
--- @param a number The tested value.
--- @param b number The expected value.
--- @param epsilon number? The tolerance to use. Defaults to 1e-6.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert_approx_eq(a, b, epsilon, message, level)
	epsilon = epsilon or 1e-6
	if to_big then
		if a == nil and b == nil then
			return
		end
		Balatest.assert(
			a ~= nil and b ~= nil,
			message or ("Expected " .. tostring(a) .. " to be within " .. tostring(epsilon) .. " of " .. tostring(b)),
			(level or 2) + 1
		)

		a = to_big(a)
		b = to_big(b)
		epsilon = to_big(epsilon)
	end
	Balatest.assert(
		a >= b - epsilon and a <= b + epsilon,
		message or ("Expected " .. tostring(a) .. " to be within " .. tostring(epsilon) .. " of " .. tostring(b)),
		(level or 2) + 1
	)
end

--- Asserts that two numbers are unequal. Handles Talisman jank for you.
--- @param a number The tested value.
--- @param b number The expected value.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert_neq(a, b, message, level)
	if to_big then
		Balatest.assert(
			((a == nil) == (b == nil)) and to_big(a) ~= to_big(b),
			message or ("Expected " .. tostring(a) .. " to differ from " .. tostring(b)),
			(level or 2) + 1
		)
	else
		Balatest.assert(
			a ~= b,
			message or ("Expected " .. tostring(a) .. " to differ from " .. tostring(b)),
			(level or 2) + 1
		)
	end
end

--- Asserts the amount of total round chips.
--- @param val number The tested value.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert_chips(val, message, level)
	Balatest.assert_eq(
		G.GAME.chips,
		val,
		message or ("Expected " .. tostring(val) .. " total round chips, got " .. tostring(G.GAME.chips)),
		(level or 2) + 1
	)
end

--- Asserts the amount of dollars.
--- @param val number The tested value.
--- @param message? string The message to use if the assertion fails.
--- @param level? integer The depth of this call. Use this in assertion libraries to point the blame higher in the callstack.
function Balatest.assert_dollars(val, message, level)
	Balatest.assert_eq(
		G.GAME.dollars,
		val,
		message or ("Expected $" .. tostring(val) .. " total, got " .. tostring(G.GAME.dollars)),
		(level or 2) + 1
	)
end
