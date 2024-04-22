when defined(js):
  import jsset
  import std/dom
else:
  import std/sets
import macros
import std/[hashes, options]

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
    parent: Observer
      ## Store the parent. This enables walking up the stack to find contexts
    contexts: seq[Context]
      ## All contexts that are stored in this observer

  Context = ref object of RootObj

  Computation = ref object of Observer
    ## Computation also has added callback that is called whenever the children update
    fn: Callback

proc hash*(x: Observer): Hash =
  result = hash(cast[pointer](x))

var
  listener*: Computation = nil
    ## Also tracks dependencies. But by splitting it up we can
    ## turn it off to turn off tracking for a block of code
  owner*: Observer = nil
    ## Used for tracking contexts
template observStack(body: untyped) =
  ## Stores the owner, listener and reassigns at end of body.
  ## Done so that they can be safely reassigned
  let
    prevOwner {.inject.} = owner
    prevListener {.inject.} = listener
  defer:
    owner = prevOwner
    listener = prevListener
  body

template untrack*[T: not void](body: T): T =
  ## Runs the body but causes any reads to not make it be subscribed
  var res {.noinit.}: T
  observStack:
    listener = nil
    res = body
  res

template untrack*(body: untyped): untyped =
  ## Runs the body but causes any reads to not make it be subscribed
  observStack:
    listener = nil
    body

proc initRoot*[T](body: Accessor[T]): T =
  ## A root just gives you a new section to register observers under
  ## that you can dispose of. Doesn't rerun if its dependencies change.
  ## Basically creates a new graph in the dependency tree? Use then
  ## when you don't want effects to bubble up
  observStack:
    owner = Computation(fn: body, children: initNativeSet[Observer]())
    listener = owner
    # Shouldn't register itself, we need to return a disposal function
    untrack:
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
  # Cleanups will get registered when the observer is called again.
  # So reset the list so cleanups dont hang aroudn
  body.cleanups.setLen(0)

proc initComputation(body: Callback, name = "") =
  ## Create a computation which is an effect that reruns everytime
  ## its dependencies (signals read inside it) change
  observStack:
    listener = Computation(fn: body, children: initNativeSet[Observer]())
    owner = listener
    if prevOwner != nil:
      prevOwner.children.incl owner
    body()



proc run(x: Computation) =
  ## Runs a computation. First disposes of the previous
  ## run so that it runs freshly (as if it wasn't ran before)
  x.dispose()
  observStack:
    # Set the current observer to be us so that
    # children know who to register themselves to
    owner = x
    listener = x
    x.fn()


template staticSignal[T](val: T): Accessor[T] =
  ## Signal that just returns a value
  proc fakeGet(): T {.nimcall.} = val
  fakeGet

proc createSignal*[T](init: T): Signal[T] =
  var subscribers = initNativeSet[Computation]()
  const hasVal = T isnot void
  when hasVal:
    var value = init
  let read = proc (): T {.tags: [ReadSignal].}=
    # Add the current context to our subscribers.
    # This is done so we only rerender the closest context needed
    if listener != nil:
      subscribers.incl listener
    when hasVal: value

  let write = proc (newVal: T) =
    when hasVal:
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
  listener.cleanups &= x

template select*(s: Accessor, selector: untyped): Accessor =
  createMemo do ():
    let it = s()
    selector

when defined(js):
  export jsset
else:
  export sets

