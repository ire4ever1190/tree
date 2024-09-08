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

example:
  import src/fogair
  import std/sequtils

  type
    Todo = ref object
      id: int
      title: string
      completed: bool

  let (list, setList) = createSignal[seq[Todo]](@[])

  proc ItemAdder(): Element =
    var inputElem: InputElement
    gui:
      tdiv:
        input(ref inputElem)
        button():
          proc click() =
            setList(list() & Todo(id: 1, title: $inputElem.value))
          text("Add TODO")


  proc Example(): Element =
    gui:
      fieldset:
        legend:
          text("TODO list")
        ItemAdder()
        for item in list():
          tdiv:
            input(`type` = "checkbox", id = $item.id, checked=item.completed):
              proc change(ev: Event) =
                # This isn't good practise since it won't cause rerenders.
                # But this simplifies the demo
                item.completed = ev.target.checked

            label(`for` = $item.id):
              text(item.title)

const todoApp = initExampleBlock("todo", "-b:js")

checkMultiBlock(start)
