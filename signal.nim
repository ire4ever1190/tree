import std/sets
import macros


type
  Accessor[T] = proc (): T
  Setter[T] = proc (newVal: T)
  Signal[T] = tuple[get: Accessor[T], set: Setter[T]]

var listeners: seq[proc ()] = @[]

template staticSignal[T](val: T): Accessor[T] =
  proc fakeGet(): T {.nimcall.} = val
  fakeGet

proc createSignal[T](init: T): Signal[T] =
  var subscribers = initHashSet[proc ()]()

  var value = init
  let read = proc (): T =
    # Add the current context to our subscribers.
    # This is done so we only rerender the closest context needed
    if listeners.len > 0:
      subscribers.incl listeners[^1]
    value

  let write = proc (newVal: T) =
    value = newVal
    # Run every context that is subscribed
    for subscriber in subscribers:
      subscriber()

  return (read, write)


proc createEffect(callback: proc ()) =
  listeners &= callback
  callback()
  discard listeners.pop()

proc createMemo[T](callback: proc (): T): (proc (): T) =
  let (getVal, setVal) = createSignal(default(T))
  createEffect() do ():
    setVal(callback())
  result = getVal

import strformat, htmlgen

type
  Node = ref object
    html: string
    count: Signal[int]

proc foo(x: Accessor[int]) =
  echo x()

let (count, setCount) = createSignal(9)
foo(staticSignal(9))
foo(count)


