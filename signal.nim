when defined(js):
  import jsset
  import std/dom
else:
  import std/sets
import macros
import std/hashes

type
  NativeSet[T] = (when defined(js): JSSet[T] else: HashSet[T])

proc initNativeSet[T](): NativeSet[T] =
  when defined(js): newJSSet[T]()
  else: initHashSet[T]()

type
  Accessor[T] = proc (): T
  Setter[T] = proc (newVal: T)
  Signal[T] = tuple[get: Accessor[T], set: Setter[T]]

  Callback = proc ()

  Observer = ref object of RootObj
    parent: Observer
    cleanups: seq[Callback]
    listeners: seq[Callback]
    children: NativeSet[Observer]
      ## Children observers so that we can call dispose and clear everything

  Computation = ref object of Observer
    fn: Callback

proc hash(x: Observer): Hash =
  result = hash(cast[int](x.addr))

var observer: Observer = Observer(children: initNativeSet[Observer]())

proc initRoot(body: Callback) =
  let prev = observer
  body()
  observer = prev

proc dispose(body: Observer) =
  for child in body.children:
    dispose child

  for cleanup in body.cleanups:
    cleanup()

proc initComputation(body: Callback) =
  let prev = observer
  observer = Computation(fn: body, children: initNativeSet[Observer]())
  prev.children.incl observer
  body()
  observer = prev

proc run(x: Computation) =
  x.dispose()
  x.fn()

template staticSignal[T](val: T): Accessor[T] =
  proc fakeGet(): T {.nimcall.} = val
  fakeGet

proc createSignal[T](init: T): Signal[T] =
  var subscribers = initNativeSet[Computation]()

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
    let old = subscribers
    for subscriber in old:
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

when defined(js):

  proc insert(parent: Element, child: Element, current: Element = nil) =
    if current == nil:
      parent.appendChild(child)
    else:
      parent.replaceChild(child, parent.firstChild)

  proc insert(parent: Element, child: Accessor[Element], current: Element = nil) =
    let current = child()
    createEffect do ():
      parent.insert(child(), current)

  proc registerEvent(x: EventTarget, name: cstring, handler: proc (ev: Event)) =
    x.addEventListener(name, handler)
    onCleanup do ():
      echo "Unregistering"
      x.removeEventListener(name, handler)

  proc counter(): Element =
    let (count, setCount) = createSignal(0)

    let btn = document.createElement("button")

    btn.registerEvent("click") do (ev: Event):
      setCount(count() + 1)

    createEffect do ():
      btn.innerText = cstring($count())

    return btn

  proc app(): auto =
    let (showCounter, setShowCounter) = createSignal(true)

    proc handleClick(ev: Event) =
      echo "Clicked"
      setShowCounter(not showCounter())

    return createMemo do () -> Element:
      if showCounter():
        let btn = document.createElement("button")
        btn.innerText = "Hello"
        btn.registerEvent("click", handleClick)
        return btn
      else:
        let btn = document.createElement("button")
        btn.innerText = "Goodbye"
        btn.registerEvent("click", handleClick)
        return btn

  document.body.insert(app())



