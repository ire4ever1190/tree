when defined(js):
  import jsset
else:
  import std/sets
import macros
import std/hashes


type
  Accessor[T] = proc (): T
  Setter[T] = proc (newVal: T)
  Signal[T] = tuple[get: Accessor[T], set: Setter[T]]

  Callback = proc ()

  Observer = ref object of RootObj
    parent: Observer
    cleanups: seq[Callback]
    listeners: seq[Callback]

  Computation = ref object of Observer
    fn: Callback

proc hash(x: Observer): Hash =
  result = hash(cast[int](x.addr))

var observer: Observer = Observer()

proc initRoot(body: Callback) =
  let prev = observer
  body()
  observer = prev

proc initComputation(body: Callback) =
  let prev = observer
  observer = Computation(fn: body)
  body()
  observer = prev

proc run(x: Computation) =
  for cleanup in x.cleanups:
    cleanup()
  x.fn()

template staticSignal[T](val: T): Accessor[T] =
  proc fakeGet(): T {.nimcall.} = val
  fakeGet

proc createSignal[T](init: T): Signal[T] =
  var subscribers = when defined(js): newJSSet[Computation]() else: initHashSet[Computation]()

  var value = init
  let read = proc (): T =
    # Add the current context to our subscribers.
    # This is done so we only rerender the closest context needed
    if observer != nil and observer of Computation:
      subscribers.incl Computation(observer)
    value

  let write = proc (newVal: T) =
    value = newVal
    # Run every context that is subscribed
    for subscriber in subscribers:
      subscriber.run()

  return (read, write)

proc createEffect(callback: proc ()) =
  initComputation(callback)

proc createMemo[T](callback: Accessor[T]): Accessor[T] =
  let (getVal, setVal) = createSignal(default(T))
  createEffect() do ():
    setVal(callback())
  result = getVal

proc onCleanup(x: Callback) =
  observer.cleanups &= x

# import std/dom


# proc counter(): Element =
#   let (count, setCount) = createSignal(0)
#
#   let btn = document.createElement("button")
#
#   btn.onclick = proc (e: Event) =
#     setCount(count() + 1)
#
#   createEffect do ():
#     btn.innerText = cstring($count())
#
#   return btn
#
# document.body.appendChild(counter())


let (count, setCount) = createSignal(0)

let countSquared = createMemo do () -> int:
  echo "Recomputing"
  onCleanup do ():
    echo "Cleaning up"
  count() * count()

echo countSquared()
setCount(9)
echo countSquared()
echo countSquared()
echo countSquared()

