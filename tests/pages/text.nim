when defined(js):
  import tree
  import std/dom

  proc App(): Element =
    gui:
      tdiv:
        p(id="commandCall"):
          text "Hello"
        p(id="functionCall"):
          text("World")

  discard document.getElementById("root").insert(App)

else:
  import utils

  proc tests*(d: FirefoxDriver) {.async.} =
    test "Command Call":
      check d.selectorText("#commandCall").await() == "Hello"

    test "Function call":
      check d.selectorText("#functionCall").await() == "World"
