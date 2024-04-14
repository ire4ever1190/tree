import signal
import std/unittest

test "Setting a signal updates it":
  let (read, write) = createSignal("foo")
  assert read() == "foo"
  write("bar")
  assert read() == "bar"

test "Effect is called when dependencies update":
  let (read, write) = createSignal(0)
  var timesCalled = 0

  createEffect do ():
    discard read()
    timesCalled += 1

  check timesCalled == 1
  write(1)
  check timesCalled == 2
  write(2)
  check timesCalled == 3

test "untrack stops subscriptions":
  let (read, write) = createSignal(0)
  var timesCalled = 0
  createEffect do ():
    untrack:
      discard read()
    timesCalled += 1
  for i in 0..10:
    write(i)
  check timesCalled == 1

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
