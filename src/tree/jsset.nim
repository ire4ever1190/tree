##[
  Basic bindings to built-in JS `Set` type
]##

type
  JSSet*[T] {.importc.} = ref object

  Iterator[T] {.importc.} = ref object

  IteratorResult[T] {.importc.} = ref object
    done {.importc.}: bool
    value {.importc.}: T

proc newJSSet*[T](): JSSet[T] {.importjs: "(new Set())".}

proc contains*[T](s: JSSet[T]): bool {.importjs: "#.has(#)".}

proc incl*[T](s: JSSet[T], val: T) {.importjs: "#.add(#)".}

proc entries*[T](s: JSSet[T]): Iterator[array[2, T]] {.importjs: "#.entries()".}

proc next[T](iter: Iterator[T]): IteratorResult[T] {.importjs: "#.next()".}

proc clear*(s: JSSet) {.importjs: "#.clear()".}

iterator items*[T](s: JSSet[T]): T =
  let iter = s.entries()
  while true:
    let res = iter.next()
    if res.done:
      break
    yield res.value[0]

