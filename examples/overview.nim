## # Overview

import docUtils

const start = initExampleBlock("start", "-b:js")

##[
  This serves as a quick intro into how to use this framework. First you'll need to learn
  about the basic primitive which are signals. We create them using [createSignal] and they return
  a read, write pair
]##

multiBlock start:
  import tree
  let (read, write) = createSignal(0)
  echo read() # We read by calling it like a function
  write(1) # And update it by giving it a new value

##[
  This can then be combined with [createEffect] to get something that is actually usable.
  `createEffect` will track the signals that it is dependent on and will then rerun when
  the value of any signal changes (It also runs when initially created, this is so it can find its dependencies)
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


example:
  import tree
  import std/sequtils

  type
    Todo = ref object
      title: string

  let (list, setList) = createSignal[seq[Todo]](@[])

  proc ItemAdder(): Element =
    var inputElem: InputElement
    gui:
      tdiv:
        input(ref inputElem)
        button():
          proc click() =
            setList(list() & Todo(title: $inputElem.value))
          "Add TODO"

  proc Example(): Element =
    gui:
      fieldset:
        legend: "TODO list"
        ItemAdder()
        ul:
          for idx, item in list():
            li:
              text(item.title)
              proc click(ev: Event) =
                # Filter out the current item
                var newItems: seq[Todo] = @[]
                let currItems = list()
                for i in 0 ..< currItems.len:
                  if i != idx:
                    newItems &= currItems[i]
                setList(newItems)

checkMultiBlock(todoApp)

checkMultiBlock(start)

