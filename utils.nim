import std/asyncjs
import signal

type
  AsyncState = enum
    InProgress
    Finished
    Errored

  AsyncSignal[T] = object
    case state: AsyncState
    of InProgress: discard
    of Finished:
      value: T
    of Errored:
      error: Error


proc asyncSignal*[T](fut: Future[T]): Accessor[T]
  let (read, write) = createSignal(AsyncSignal(state: InProgress))

  fut
    .then(
        onSuccess: (proc (val: T) = write(AsyncSignal(state: Finished, value: val))),
        onReject: (proc (err: Error) = write(AsyncSignal(state: Errored, error: err)))
    )
  return read
