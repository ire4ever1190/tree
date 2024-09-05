when defined(js):
  import jsset
  import std/dom
else:
  import std/sets
import std/[macros, effecttraits]
import std/[hashes, options]

# TODO: Rename to signals

type
  NativeSet[T] = (when defined(js): JSSet[T] else: HashSet[T])

proc initNativeSet[T](): NativeSet[T] =
  when defined(js): newJSSet[T]()
  else: initHashSet[T]()

type
  ReadEffect* = object of RootEffect
    ## Effect to show that a proc reads a signal
  Accessor*[T] = proc (): T
  Setter*[T] = proc (newVal: T)
  # Issue, the proc type needs to be here or else the tags are not carried across?
  # Unsure if its an effect bug or generic instanitation bug
  Signal*[T] = tuple[get: proc (): T {.tags: [ReadEffect].}, set: Setter[T]]


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
  bind hash
  var subscribers = initNativeSet[Computation]()
  const hasVal = T isnot void
  when hasVal:
    var value = init
  # TODO: See why this gives undeclared identifier
  # bind isn't working
  bind ReadEffect
  let read = proc (): T {.tags: [ReadEffect].}=
    # Add the current context to our subscribers.
    # This is done so we only rerender the closest context needed
    if listener != nil:
      subscribers.incl listener
    when hasVal: value

  let write = proc (newVal: T) =
    when hasVal:
      # Don't update if its the same value
      if value == newVal: return
      value = newVal
    # Run every context that is subscribed
    let old = subscribers
    for subscriber in old:
      subscriber.run()

  return (read, write)

proc inc*[T: SomeInteger](signal: Signal[T], amount: T = 1) =
  ## Increments a value. This doesn't subscribe to the signal
  untrack:
    signal.set(signal.get() + amount)

proc createEffect*(callback: proc ()) {.effectsOf: callback.}=
  ## Wrapper around initComputation
  initComputation(callback)

proc createMemo*[T](callback: Accessor[T]): Accessor[T] {.effectsOf: callback.}=
  ## Memo will return the last value of the computation.
  ## Automatically updates when its dependencies change
  let (getVal, setVal) = createSignal(default(T))
  createEffect() do ():
    setVal(callback())
  result = getVal

proc onCleanup*(x: Callback) {.effectsOf: x.}=
  ## Registers a function to be called when the current computation is cleaned
  listener.cleanups &= x

macro performsRead*(x: proc): bool =
  ## Returns true if `proc` `x` reads a signal. If the `proc` has `RootEffect` then
  ## thats also considered reading a signal because its unknown if it does.
  ## Used for optimisation purposes such as eliding effects
  if x.kind != nnkSym:
    "Must be a symbol passed".error(x)
  let list = x.getTagsList()
  result = newLit false
  for tag in list:
    # It's very important we are pessimesitc about effects since we don't want to say that something
    # doesn't perform a read just because the compiler says it doesn't know
    if tag.eqIdent(bindSym"ReadEffect") or tag.eqIdent("UncomputedEffects") or tag.eqIdent(bindSym"RootEffect"):
      return newLit true

when defined(js):
  export jsset
else:
  export sets

