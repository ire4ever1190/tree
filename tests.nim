import signal
import std/unittest

test "Cleanups are called":
  var times = 0
  let (count, setCount) = createSignal(0)
  createEffect do ():
    onCleanup do ():
      times += 1
    discard count()
  const n = 10
  for i in 0..<n:
    setCount(i)
  check times == n - 1
