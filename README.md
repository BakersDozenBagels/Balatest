# Balatest - Unit Testing for Balatro

Balatest is a unit testing framework for Balatro mods. See [Bakery's unit tests](https://github.com/BakersDozenBagels/BalatroBakery/tree/main/test) for example code using Balatest.

## How To Use

First, register some unit tests with `Balatest.TestPlay` (see below). Then, to run tests, execute `Balatest.run_tests()` (I recommend using [DebugPlus](https://github.com/WilsontheWolf/DebugPlus) to do so). Balatest will put test results in the console/log. You can also only run the tests from a given mod (`Balatest.run_tests 'Bakery'`) or from a category in a mod (`Balatest.run_tests('Bakery', 'blinds')`).

## Writing Tests

A test in Balatest is fundamentally a [challenge](https://github.com/Steamodded/smods/wiki/SMODS.Challenge). Many of the keys in a challenge will also work in a test. Balatest will automatically begin the challenge and navigate to the Small Blind (note that every blind is Small by default). From there, `test.execute()` is called, where you will play, discard, navigate rounds, etc. Finally, `test.assert()` is called to evaluate the results of the test.

### `test.execute()`

Here you will put some actions in a queue to set up the test. Note that this queue is *not* the default one; use `Balatest.q()` to add to it (`q` accepts bare functions as well as `Event`s for added convenience).

Balatest also provides some pre-built events for you (each of these adds to the queue for you):
- `Balatest.next_round()` ends the round and navigates to the next one.
- `Balatest.end_round()` ends the round and waits on the evaluation screen.
- `Balatest.cash_out()` cashes out the round evaluation screen.
- `Balatest.exit_shop()` exits the shop.
- `Balatest.start_round()` selects the next blind.
- `Balatest.play_hand { '2S', '10H' }` plays those cards.
- `Balatest.discard { 'Ts', 'Qc' }` discards those cards.

### `test.assert`

Here you will write some assertions on the final state of the test. Balatest provides a few helpers for this:
- `Balatest.assert(bool, message?)` is a bare assertion.
- `Balatest.assert_eq(a, b, message?)` asserts that two numbers are equal with or without Talisman.
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

# Advanced Features

- Specify `blind = 'bl_wheel'` to make every blind The Wheel. By default, every blind is a Small Blind.
- Specify `name = 'something'` to give your test a descriptive name. Names are automatically prefixed with your mod's ID.
- Specify `category = 'my_category'` to be able to run a subset of your tests.
- Specify `requires = { 'another_name' }` to only run your test once the one with that name has passed.
- Use `Balatest.run_test 'mod_id_test_name'` to run a single test.
- Check `Balatest.current_test` for the name of the currently running test.
- Inspect `Balatest.done` for more detailed results of your tests.

# Current Limitations

Currently, it's quite annoying to write tests using any of the following:
- Using a consumable
- Tags
- Skipping Blinds
- Anything in the shop
- Certain modded object types
Better support for these will be coming soon as I increase coverage on Bakery.