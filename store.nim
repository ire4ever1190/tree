import signal

type
  Store[T] = object
    wires: Signal[void]
    data: T

proc createStore*[T](init: T): Store[T] =
  result.wires = createSignal[void]()
  result.data = init

proc updated(s: Store) =
  ## Notifies to all listeners that the store has been updated
  s.wires.set()

proc subscribe*(s: Store) =
  ## Subscribe the current context so it runs when the store is updated
  s.wires.get()

template select*(s: Store, selector: untyped): Accessor =
  createMemo do () -> auto:
    s.subscribe()
    let it {.inject.} = s.data
    selector
