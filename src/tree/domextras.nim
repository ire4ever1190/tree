import dom

type
  BaseElement* {.importc.} = ref object of Element
    role*: cstring

  AElement* {.importc.} = ref object of Element
    href*: cstring

  ButtonElement* {.importc.} = ref object of BaseElement
    autofocus: bool
    formaction: cstring
    formenctype: cstring
    formmethod: cstring
    formnovalidate: bool
    formtarget: cstring
    # TODO: popover stuff
    `type`: cstring
    value: cstring

  ImgElement* {.importc.} = ref object of ImageElement
    loading*: cstring

  LabelElement* {.importc.} = ref object of BaseElement
    `for`*: cstring

proc form(btn: ButtonElement): dom.FormElement {.importjs: "#.form".}
proc name*(event: Event): cstring {.importjs: "#.name".}
proc `kind=`*(e: InputElement, kind: cstring) {.importjs: "#.type = #".}
proc prepend*(e: Element, children: Node) {.importjs: "#.prepend(@)"}
