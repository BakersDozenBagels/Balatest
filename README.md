# Balatest - Unit Testing for Balatro

Balatest is a unit testing framework for Balatro mods. See [Bakery's unit tests](https://github.com/BakersDozenBagels/BalatroBakery/tree/main/test) for example code using Balatest.

## How To Use

First, register some unit tests with `Balatest.TestPlay` (see below). Then, to run tests, execute `Balatest.run_tests()` (I recommend using [DebugPlus](https://github.com/WilsontheWolf/DebugPlus) to do so). Balatest will put test results in the console/log. You can also only run the tests from a given mod (`Balatest.run_tests 'Bakery'`) or from a category in a mod (`Balatest.run_tests('Bakery', 'blinds')`).

## Writing Tests

A test in Balatest is fundamentally a [challenge](https://github.com/Steamodded/smods/wiki/SMODS.Challenge). Many of the keys in a challenge will also work in a test. Balatest will automatically begin the challenge and navigate to the Small Blind (note that every blind is Small by default). From there, `test.execute()` is called, where you will play, discard, navigate rounds, etc. Finally, `test.assert()` is called to evaluate the results of the test.

### `execute`

Here you will put some actions in a queue to set up the test. Note that this queue is *not* the default one; use `Balatest.q()` to add to it (`q` accepts bare functions as well as `Event`s for added convenience. Additionally, it will automatically `return true` for you unless you explicitly `return false`).

Balatest also provides some pre-built events for you (each of these adds to the queue for you):
- `Balatest.next_round()` ends the round and navigates to the next one.
- `Balatest.end_round()` ends the round and waits on the evaluation screen.
- `Balatest.cash_out()` cashes out the round evaluation screen.
- `Balatest.exit_shop()` exits the shop.
- `Balatest.start_round()` selects the next blind.
- `Balatest.skip_blind(for_tag)` skips the next blind for the given tag (by key).
- `Balatest.play_hand { '2S', '10H' }` plays those cards in that order. Note that this fails if the cards are not in hand.
- `Balatest.discard { 'Ts', 'Qc' }` discards those cards. Note that this fails if the cards are not in hand.
- `Balatest.highlight { '2S', '10H' }` highlights those cards in that order. Note that this fails if the cards are not in hand.
- `Balatest.unhighlight_all()` unhighlights the hand.
- `Balatest.use(card, instant)` uses a consumable. E.g. `Balatest.use(G.consumeables.cards[1])` (you can also pass a function as in `buy`)
- `Balatest.buy(func)` buys something from the shop. E.g. `Balatest.buy(function() return G.shop_jokers.cards[1] end)`
- `Balatest.hook(obj, name, func)` hooks a function until the test concludes. See below for more information.
- `Balatest.hook_raw(obj, name, new)` overwrites an object until the test concludes.
- `Balatest.wait_for_input(state, front)` waits until the game will accept input.
- `Balatest.reload()` saves and loads the game as if by returning to the main menu.
- `Balatest.wait()` waits until everything currently in the standard event queue completes.

### `assert`

Here you will write some assertions on the final state of the test. Balatest provides a few helpers for this:
- `Balatest.assert(bool, message?)` is a bare assertion.
- `Balatest.assert_eq(a, b, message?)` asserts that two numbers are equal with or without Talisman.
- `Balatest.assert_neq(a, b, message?)` asserts that two numbers are unequal with or without Talisman.
- `Balatest.assert_chips(num, message?)` asserts that `G.GAME.chips` is equal to the supplied number.

## Example Test

```lua
Balatest.TestPlay {
    jokers = { 'j_joker' }, -- Start with a Joker
    execute = function()
        Balatest.play_hand { '2S' } -- Play a High Card
    end,
    assert = function()
        Balatest.assert_chips(35) -- Total round score, *not* the last hand
    end
}
```

## Default Values

Balatest will run each test with the following defaults:
- `back = 'Red Deck'`
- `stake = 1`
- `seed = nil`
- `jokers = {}`
- `consumeables = {}`
- `vouchers = {}`
- `dollars = 0` (Starting money)
- `discards = 999`
- `hands = 999`
- `hand_size = 52`
- `modifiers = {}` (`challenge.rules.modifiers`)
- `custom = {}` (`challenge.rules.custom`)
- `deck = nil`
- `blind = 'bl_small'`
- `no_auto_start = false`

# Advanced Features

- Specify `blind = 'bl_wheel'` to make every blind The Wheel. By default, every blind is a Small Blind.
- Specify `name = 'something'` to give your test a descriptive name. Names are automatically prefixed with your mod's ID.
- Specify `category = 'my_category'` to be able to run a subset of your tests. You can specify multiple categories in a table.
- Use `Balatest.run_test { ... }` to run a single test not defined elsewhere.
- Use `Balatest.run_test 'mod_id_test_name'` to run a single test.
- Use `Balatest.run_test('something', function)` to use a custom logger for the test's results.
- Check `Balatest.current_test` for the name of the currently running test.
- Check `Balatest.current_test_object` for the whole config of the currently running test.
- Inspect `Balatest.done` for more detailed results of your tests.

## `Balatest.hook`

Sometimes it's necessary to hook a function in the middle of a test, for example to control RNG.
Balatest provides a fixture to do this and automatically unhook the functions later.

Consider the following quite silly test:

```lua
Balatest.run_test {
    consumeables = { 'c_judgement' },
    execute = function()
        Balatest.hook(_G, 'create_card', function(orig, t, a, l, r, k, s, forced_key, ...)
            return orig(t, a, l, r, k, s, 'j_chicot', ...)
        end)
        Balatest.use(G.consumeables.cards[1])
    end,
    assert = function()
        Balatest.assert_eq(#G.consumeables.cards, 0)
        Balatest.assert_eq(#G.jokers.cards, 1)
        Balatest.assert(G.jokers.cards[1].config.center.key == 'j_chicot')
    end
}
```

Here, we force the global function `create_card` to create a Chicot (which otherwise cannot spawn from Judgement).
Note that the first argument to the new function is the previous function.

```lua
Balatest.run_test {
    consumeables = { 'c_judgement', 'c_judgement' },
    execute = function()
        Balatest.hook(_G, 'create_card', function(orig, t, a, l, r, k, s, forced_key, ...)
            return orig(t, a, l, r, k, s, 'j_perkeo', ...)
        end)
        Balatest.use(G.consumeables.cards[1])
        Balatest.hook(_G, 'create_card', function(orig, t, a, l, r, k, s, forced_key, ...)
            return orig(t, a, l, r, k, s, 'j_caino', ...)
        end)
        Balatest.use(G.consumeables.cards[2]) -- The card is looked up before the other one gets destroyed.
    end,
    assert = function()
        Balatest.assert_eq(#G.consumeables.cards, 0)
        Balatest.assert_eq(#G.jokers.cards, 2)
        Balatest.assert(G.jokers.cards[1].config.center.key == 'j_perkeo')
        Balatest.assert(G.jokers.cards[2].config.center.key == 'j_caino')
    end
}
```

Here, we hook the same function twice. Note that when the second hook is applied, the first hook gets removed.
Also note that the application of the hook is queued.
After running these tests, even if they fail, the function will be what it was originally.
