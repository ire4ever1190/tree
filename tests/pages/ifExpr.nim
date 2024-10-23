when defined(js):
  import tree
  import std/dom

  proc App(): Element =
    let (flag, setFlag) = createSignal(false)
    gui:
      tdiv:
        button(id="btnFlip"):
          proc click = setFlag(not flag())
        # Test elements can be conditional
        if flag():
          p(id="toggled"):Red
            text "I'm shown"
        # Test that elements get cleaned
        if flag():
          p(id="whenTrue"):
            text("Its true")
        else:
          p(id="whenFalse"):
            "Its false"
        # Test that they act like a block
        if true:
          p(id="block1"): "This is shown"
          p(id="block2"): "This too"

  App.renderTo("root")

else:
  import utils

  proc tests*(d: FirefoxDriver) {.async.} =
    template testForState(state: bool) =
      test "Flipped element is correct":
        check d.elementExists("#toggled").await() == state

      test "The " & $state & " element is shown":
        check d.elementExists("#whenFalse").await() != state
        check d.elementExists("#whenTrue").await() == state

    testForState(false)
    await d.selectorClick("#btnFlip")
    testForState(true)
    # Check they can handle cleaning up after
    await d.selectorClick("#btnFlip")
    testForState(false)

    test "Block is shown":
      check d.selectorText("#block1").await() == "This is shown"
      check d.selectorText("#block2").await() == "This too"
