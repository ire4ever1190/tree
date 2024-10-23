type
  Colour = enum
    Red
    Green
    Blue


when defined(js):
  import tree
  import std/dom

  proc App(): Element =
    let (colour, setColour) = createSignal(Red)
    let (counter, setCounter) = createSignal(0)
    proc setAndRet(): int =
      setCounter(3)
      counter()
    gui:
      tdiv:
        button(id="btnInc"):
          proc click =
            setColour(succ colour())
        p(id="colour"):
          case colour()
          of Red: "Red"
          of Green: "Green"
          of Blue: "Blue"

        # Make sure that an else branch is handled
        case colour()
        of Green:
          p(id="onlyGreen"):
            text "It's not green"
        else: nil

        p(id="discardStmts"):
          case colour()
          of Green:
            # Make sure discard statements are called
            discard setAndRet()
            "test"
          of Blue:
            # Small logic error I had where I discarded the result if
            # the first element was a discard statement
            discard 9
            $counter()
          else: nil

  App.renderTo("root")

else:
  import utils
  import std/enumutils

  proc tests*(d: FirefoxDriver) {.async.} =
    test "Can go through all branches":
      for c in Colour:
        # Check the secondary case expression
        if c == Green:
          check d.selectorText("#onlyGreen").await() == "It's not green"
        else:
          check not await d.elementExists("#onlyGreen")

        # Check the main case expression is correct
        check d.selectorText("#colour").await() == symbolName(c)
        await d.selectorClick("#btnInc")

    test "Discard statements":
      for c in Colour:
        let text = d.selectorText("#discardStmts").await()
        let expected = case c
                       of Green: "test"
                       of Red: ""
                       of Blue: "3"
        checkpoint $c & ": " & text & " " & expected
        check text == expected

