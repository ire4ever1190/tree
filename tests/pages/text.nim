when defined(js):
  import tree
  import std/dom

  proc myName(): string = "Jake"

  proc App(): Element =
    gui:
      tdiv:
        p(id="commandCall"):
          text "Hello"
        p(id="functionCall"):
          text("World")
        p(id="stringChild"):
          "Foo Bar"
        # Calls should also be supported since
        # ```
        # gui:
        #  "string"
        # ```
        # works so a function call should get interpreted the same
        p(id="stringChildFromCall"):
          myName()

  App.renderTo("root")

else:
  import utils

  proc tests*(d: FirefoxDriver) {.async.} =
    test "Command Call":
      check d.selectorText("#commandCall").await() == "Hello"

    test "Function Call":
      check d.selectorText("#functionCall").await() == "World"

    test "String Child":
      check d.selectorText("#stringChild").await() == "Foo Bar"

    test "String Child Call":
      check d.selectorText("#stringChildFromCall").await() == "Jake"
