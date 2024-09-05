import fogair/signal

proc countUpdates*(body: proc ()): Accessor[int] =
  ## Returns an accessor which counts how many times body has
  ## updated
  # Initialised to -1 since it will get read the first time
  let (read, write) = createSignal(-1)
  createEffect() do ():
    body()
    untrack:
      write(read() + 1)
  return read
