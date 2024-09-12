when defined(js):
  import tree
  import std/dom

  proc App(): Element =
    let (number, setNumber) = createSignal(3)
    gui:
      tdiv:
        button(id="btnInc"):
          text "Increment"
          proc click = setNumber(number() + 1)

        button(id="btnDec"):
          text "Decrement"
          proc click = setNumber(max(number() - 1, 0))

        tdiv(id="justLoop"):
          for i in 1..number():
            p(class="item"):
              text($i)

        tdiv(id="elementBefore"):
          p(class="before"):
            text "foo"
          for i in 1..number():
            p(class="item"):
              text($i)

        tdiv(id="elementAfter"):
          for i in 1..number():
            p(class="item"):
              text($i)
          p(class="after"):
            text "bar"

        tdiv(id="elementsAround"):
          p(class="before"):
            text "foo"
          for i in 1..number():
            p(class="item"):
              text($i)
          p(class="after"):
            text "bar"

        tdiv(id="treeLoops"):
          for i in 1..number():
            p(class="item-1", style="color: red"):
              text($i)
          for i in 1..number():
            p(class="item-2", style="color: green"):
              text($i)
          for i in 1..number():
            p(class="item-3", style="color: blue"):
              text($i)


  App.renderTo("root")

else:
  import utils
  import std/strformat

  proc tests*(d: FirefoxDriver) {.async.} =
    proc hasElements(id: string, hasBefore, hasAfter: bool, num: int): Future[bool] {.async.} =
      ## Performs all the checks the elements are where they should be
      template chRet(body: untyped): untyped =
        check body
        if not body: return false
      if hasBefore:
        chRet d.selectorText(fmt"#{id} .before").await() == "foo"
      if hasAfter:
        chRet d.selectorText(fmt"#{id} .after").await() == "bar"
      # Check all the numbers have been inserted
      var i = 0
      for element in await d.getElementsByCssSelector(fmt"#{id} .item"):
        i += 1
        chRet d.getElementText(element).await() == $i
      chRet i == num
      return true

    template makeTestBatch(n: int) =
      ## Generates a batch of test cases to check every orientation
      test "Just for loop n=" & $n:
        check await hasElements("justLoop", false, false, n)

      test "With element before: n=" & $n:
        check await hasElements("elementBefore", true, false, n)

      test "With element after: n=" & $n:
        check await hasElements("elementAfter", false, true, n)

      test "With elements around: n=" & $n:
        check await hasElements("elementsAround", true, true, n)

      test "Loops all around: n=" & $n:
        for i in 1..3:
          var count = 0
          for element in await d.getElementsByCssSelector("#treeLoops .item-" & $i):
            count += 1
            check d.getElementText(element).await() == $count
          check count == n

    # Run the tests
    makeTestBatch(3)
    await d.selectorClick("#btnInc")
    # Test the loops can properly expand
    makeTestBatch(4)
    await d.selectorClick("#btnDec")
    await d.selectorClick("#btnDec")
    # and shrink
    makeTestBatch(2)
    # and handle nothing
    await d.selectorClick("#btnDec")
    await d.selectorClick("#btnDec")
    makeTestBatch(0)
    # And handle coming back from nothing
    await d.selectorClick("#btnInc")
    makeTestBatch(1)
