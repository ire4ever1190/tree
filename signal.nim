when defined(js):
  import jsset
  import std/dom
else:
  import std/sets
import macros
import std/[hashes, options, asyncdispatch]

type
  NativeSet[T] = (when defined(js): JSSet[T] else: HashSet[T])

proc initNativeSet[T](): NativeSet[T] =
  when defined(js): newJSSet[T]()
  else: initHashSet[T]()

type
  ReadSignal* = object
    ## Effect to show that a proc reads a signal
  Accessor*[T] = proc (): T
  Setter[T] = proc (newVal: T)
  Signal[T] = tuple[get: Accessor[T], set: Setter[T]]


  Callback = proc ()

  Observer = ref object of RootObj
    cleanups: seq[Callback]
      ## List of functions that need to be called when disposed to cleanup
      ## any handles that this observer has
    children*: NativeSet[Observer]
      ## Children observers so that we can call dispose and clear everything

  Computation = ref object of Observer
    ## Computation also has added callback that is called whenever the children update
    fn: Callback

proc hash*(x: Observer): Hash =
  result = hash(cast[pointer](x))

var observer* = Observer(children: initNativeSet[Observer]())
  ## The current observer

template observStack(name: string, body: untyped) =
  let prev {.inject.} = observer
  body
  observer = prev

proc initRoot*[T](body: Accessor[T], name = ""): T =
  ## A root just gives you a new section to register observers under
  ## that you can dispose of. Doesn't rerun if its dependencies change.
  ## Basically creates a new graph in the dependency tree? Use then
  ## when you don't want effects to bubble up
  observStack(name):
    observer = Observer(children: initNativeSet[Observer]())
    # Shouldn't register itself, we need to return a disposal function
    result = body()

proc dispose(body: Observer) =
  ## Cleansup an observer by disposing of all its children and itself
  # First clear the children
  for child in body.children:
    dispose child
  # Make sure they are gone so vodo doesn't happen
  body.children.clear()
  # Now we can run our own cleanups
  for cleanup in body.cleanups:
    cleanup()

proc initComputation(body: Callback, name = "") =
  ## Create a computation which is an effect that reruns everytime
  ## its dependencies (signals read inside it) change
  observStack(name):
    observer = Computation(fn: body, children: initNativeSet[Observer]())
    prev.children.incl observer
    body()

proc run(x: Computation) =
  ## Runs a computation. First disposes of the previous
  ## run so that it runs freshly (as if it wasn't ran before)
  x.dispose()
  observStack "":
    # Set the current observer to be us so that
    # children know who to register themselves to
    observer = x
    x.fn()


template staticSignal[T](val: T): Accessor[T] =
  ## Signal that just returns a value
  proc fakeGet(): T {.nimcall.} = val
  fakeGet

proc createSignal*[T](init: T): Signal[T] =
  var subscribers = initNativeSet[Computation]()

  var value = init
  let read = proc (): T {.tags: [ReadSignal].}=
    # Add the current context to our subscribers.
    # This is done so we only rerender the closest context needed
    if observer != nil and observer of Computation:
      subscribers.incl Computation(observer)
    value

  let write = proc (newVal: T) =
    # Do nothing if they are the same
    when compiles(newVal == value):
      if newVal == value: return
    value = newVal
    # Run every context that is subscribed
    let old = subscribers
    for subscriber in old:
      subscriber.run()

  return (read, write)

proc inc*[T: SomeInteger](signal: Signal[T], amount: T = 1) =
  signal.set(signal.get() + amount)

proc createEffect*(callback: proc ()) =
  ## Wrapper around initComputation
  initComputation(callback)

proc createMemo*[T](callback: Accessor[T]): Accessor[T] =
  ## Memo will return the last value of the computation.
  ## Automatically updates when its dependencies change
  let (getVal, setVal) = createSignal(default(T))
  createEffect() do ():
    setVal(callback())
  result = getVal

proc onCleanup*(x: Callback) =
  ## Registers a function to be called when the current computation is cleaned
  observer.cleanups &= x

proc asyncSignal*[T](fut: Future[T]): Accessor[Option[T]] =
  let (readRes, setRes) = createSignal(none(string))
  fut.addCallback do (res: Future[T]):
    setRes(some res.read())
  return readRes


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

export sets


