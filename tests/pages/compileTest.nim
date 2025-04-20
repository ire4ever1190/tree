# Series of tests that more check for compilation
when defined(js):
  import tree
  import std/[dom, jscore, strformat]

  proc App(): Element =
    gui:
      tdiv(id="tupleLoop"):
        for (a, b) in [(1, 2), (3, 4)]:
          p: fmt"{a} | {b}"
else:
  import utils
  import std/strformat

  proc tests*(d: FirefoxDriver) {.async.} =
    test "Tuple loop runs correctly":
      check d.selectorText("#tupleLoop p:nth-child(1)").await() == "1 | 2"
      check d.selectorText("#tupleLoop p:nth-child(2)").await() == "3 | 4"
