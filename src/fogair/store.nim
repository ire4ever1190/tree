import signal

{.experimental: "callOperator".}


type
  Store*[T] = ref object
    wires: Signal[void]
    data: T

proc createStore*[T](init: T): Store[T] =
  result = Store[T]()
  result.wires = createSignal[void]()
  result.data = init

proc updated(s: Store) =
  ## Notifies to all listeners that the store has been updated
  s.wires.set()

proc rawGet*[T](s: Store[T]): lent T =
  ## Returns the value inside the store. Doesn't subscribe to changes.
  return s.data

proc `()`*[T](s: Store[T]): T =
  ## Returns the value in the store. Use [select] for something more fine grained
  ## Requires `{.experimental: "callOperator".}`
  s.wires.get()
  s.data

proc select*[T, R](s: Store[T], selector: proc (x: T): R): Accessor[R] {.effectsOf: selector.}=
  ## Allows you to subscribe to a subset of data. Useful when you only
  ## care about certain values within a store
  createMemo do () -> auto:
    selector(s())

proc update*[T](s: Store[T], updater: proc (x: var T)) {.effectsOf: updater, tags: [].} =
  ## Gives you a mutable version of the store that you can update.
  ## This allows making multiple edits at once that then get grouped into
  ## one update
  updater(s.data)
  s.updated()

proc update*[T](s: Store[T], newVal: T) =
  ## Updates the value inside the store
  s.data = newVal
  s.updated()

export signal
