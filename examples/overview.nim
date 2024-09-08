## Overview

import docUtils

const start = initExampleBlock("start", "-b:js")

##[
  This serves as a quick intro into how to use this framework. First you'll need to learn
  about the basic primitive which are signals. We create them using [createSignal] and they return
  a read, write pair
]##

multiBlock start:
  import fogair
  let (read, write) = createSignal(0)
  echo read() # We read by calling it like a function
  write(1) # And update it by giving it a new value

##[
  This can then be combined with [createEffect] to get something that is actually usable.
  `createEffect` will track the signals that it is dependent on and will then rerun when
  the value of any signal changes
]##

multiBlock start:
  createEffect do ():
    echo "The value is: ", read()
  write(2)
  # Outputs
  # The value is: 1
  # The value is: 2

##[
  Now lets build a TODO app!
]##

const todoApp = initExampleBlock("todo", "-b:js")

checkMultiBlock(start)
