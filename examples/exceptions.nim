##[
  # Example: Exceptions

  This is an example on how exceptions work.

  Due to how exception handling works in Nim, this only catches exceptions that are thrown during the creation of
  a widget
]##

import ./docUtils

example:
  import fogair
  import std/dom

  const defaultCount = 5

  proc Counter(x: Accessor[int]): Element =
    # If this was wrapped in a createEffect, then it would just be treated
    # as an unhandled exception
    if x() == 0:
      raise (ref CatchableError)(msg: "I hate being 0 >:(")

    gui:
      text("Everything is fine (As long as I don't become 0)")

  proc Example(): Element =
    let (count, setCount) = createSignal(defaultCount)
    # Start counting down
    var interval: Interval
    interval = setInterval(proc () =
      if count() == 0: return
      setCount(count() - 1)
    , 1000)
    # Build the GUI
    gui:
      tdiv:
        p:
          text(proc (): string = "The count is " & $count())
        tdiv:
          try:
            Counter(count)
          except CatchableError as e:
            tdiv:
              p:
                text(e.msg)
              button:
                proc click() = setCount(defaultCount)
                text("Click me to fix it")
