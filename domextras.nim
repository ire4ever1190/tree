import std/dom

type
  ButtonElement* {.importc.} = ref object of Element
    autofocus: bool
    formaction: cstring
    formenctype: cstring
    formmethod: cstring
    formnovalidate: bool
    formtarget: cstring
    # TODO: popover stuff
    `type`: cstring
    value: cstring

proc form(btn: ButtonElement): FormElement {.importc: "#.form".}
