import fogair/signal
import fogair/store
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

test "Void signal can be used":
  let (subscribe, signal) = createSignal[void]()
  var timesCalled = 0
  createEffect do ():
    subscribe()
    timesCalled += 1

  for i in 0..<10: signal()

  check timesCalled == 11

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

suite "Context":
  type
    Foo = ref object of Context
      value: int
  test "Add to context without parent":
    addContext(Foo(value: 1))

  test "Add to context with parent":
    createEffect do ():
      addContext(Foo(value: 1))

  test "Can get value from current context":
    createEffect do ():
      addContext(Foo(value: 10))
      check getContext(Foo).value == 10

  test "Can get value from parent context":
    createEffect do ():
      addContext(Foo(value: 1))
      createEffect do ():
        check getContext(Foo).value == 1
      check getContext(Foo).value == 1

  test "Can still get value after effect reran":
    createEffect do ():
      let (read, write) = createSignal(0)
      addContext(Foo(value: 2))
      createEffect do ():
        discard read()
        check getContext(Foo).value == 2
      write(1)
      write(1)
      write(1)

  test "Errors when it can't find context":
    type
      Test = ref object of Context
    expect KeyError:
      createEffect do ():
        addContext(Foo(value: 0))
        discard getContext(Test)

