when defined(js):
  import tree
  import std/dom

  proc myName(): string =
    "Jake"

  proc stringElem(): Element =
    gui:
      # Test that expressions are always converted into elements
      "hello"

  proc App(): Element =
    let (count, setCount) = createSignal(0)
    gui:
      tdiv:
        p(id="commandCall"):
          text "Hello"
        p(id="functionCall"):
          text("World")
        p(id="stringChild"):
          "Foo Bar"
        p(id="stringElem"):
          stringElem()
        # Calls should also be supported since
        # ```
        # gui:
        #  "string"
        # ```
        # works so a function call should get interpreted the same
        p(id="stringChildFromCall"):
          myName()
        # This should automatically get tracked and updated correctly
        button(id="complexString"):
          proc click() = setCount(2)
          "Count is: " & $count()

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

    test "Raw string elem":
      check d.selectorText("#stringElem").await() == "hello"

    test "String with signals":
      check d.selectorText("#complexString").await() == "Count is: 0"
      await d.selectorClick("#complexString")
      check d.selectorText("#complexString").await() == "Count is: 2"
