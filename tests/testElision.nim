import unittest
import fogair/signal


let (read, write) = createSignal[void]()

discard performsRead(read)
test "Accessor[T] has ReadSignal":
  check performsRead(read)

test "Function that reads a signal has ReadSignal":
  proc helper() =
    read()
  check performsRead(helper)

test "RootEffect gets marked as ReadSignal":
  proc callsProc(x: proc ()) =
    # Doesn't use effectsOf, so is marked as possibly having effect`
    x()
  check performsRead(callsProc)

test "Function that doesn't read a signal isn't tagged":
  proc foobar() = discard

  check not performsRead(foobar)

test "UncomputedEffects are caught":
  # Ran into an issue where the return type didn't have the tag.
  proc test[T](initial: T): proc (): T =
    proc inner(): T {.tags: [ReadEffect].} =
      return initial
    return inner
  let x = test(0)
  check performsRead(x)



