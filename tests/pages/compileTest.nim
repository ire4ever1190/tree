# Series of tests that more check for compilation
when defined(js):
  import tree
  import std/[dom, jscore, strformat]

  proc App(): Element =
    gui:
      tdiv:
        tdiv(id="tupleLoop"):
          for (a, b) in [(1, 2), (3, 4)]:
            p: fmt"{a} | {b}"

        tdiv(id="specialIdent"):
          for _ in [1, 2, 3]:
            p: "test"

        tdiv(id="specialIdentTuple"):
          for (a, _) in [(1, 2), (3, 4)]:
            p: fmt"{a}"

  App.renderTo("root")

else:
  import utils
  import std/strformat

  proc testText(d: FirefoxDriver, testName: string, ithChild: int): Future[string] {.async.} =
    d.selectorText(fmt"#{testName} p:nth-child({ithChild + 1})").await()

  proc tests*(d: FirefoxDriver) {.async.} =
    test "Tuple loop runs correctly":
      check d.testText("tupleLoop", 0).await() == "1 | 2"
      check d.testText("tupleLoop", 1).await() == "3 | 4"

    test "`_` can be used in a loop":
      for i in 0..<3:
        check d.testText("specialIdent", i).await() == "test"

    test "`_` can be used with a tuple":
      check d.testText("specialIdentTuple", 0).await() == "1"
      check d.testText("specialIdentTuple", 1).await() == "3"
