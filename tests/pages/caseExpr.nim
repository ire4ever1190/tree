type
  Colour = enum
    Red
    Green
    Blue

when defined(buildPage):
  import fogair
  import std/dom

  proc App(): Element =
    let (colour, setColour) = createSignal(Red)
    gui:
      tdiv:
        button(id="btnInc"):
          proc click =
            setColour(succ colour())
        p(id="colour"):
          case colour()
          of Red:
            text "Red"
          of Green:
            text "Green"
          of Blue:
            text "Blue"
        # Make sure that an else branch is generated
        # TODO: Make this work
        # case colour()
        # of Green:
          # p(id="onlyGreen"):
            # text "It's not green"


  discard document.getElementById("root").insert(App)

else:
  import utils
  import std/enumutils

  proc tests*(d: FirefoxDriver) {.async.} =
    test "Can go through all branches":
      for c in Colour:
        # Check the secondary case expression
        when false:
          if c == Green:
            check d.selectorText("#onlyGreen").await() == "It's not green"
          else:
            check not await d.elementExists("#onlyGreen")
        # Check the main case expression is correct
        check d.selectorText("#colour").await() == symbolName(c)
        await d.selectorClick("#btnInc")
