import std/[macros, strformat, dom, macrocache, asyncjs, sequtils]
import signal, domextras

type ElementMemo = Accessor[Element]

const builtinElements = CacheTable"fogair.elements"

macro registerElement(name: static[string], kind: typedesc): untyped =
  builtinElements[name] = kind
  # Return a proc which will create it
  let id = ident name
  result = quote do:
    proc `id`(): `kind` =
      `kind`(document.createElement(`name`))

registerElement("button", ButtonElement)
registerElement("tdiv", Element)
registerElement("input", InputElement)
registerElement("p", Element)

proc text(val: string): Element =
  Element(document.createTextNode(val))

proc add(elem: Element, child: Element) =
  if child != nil:
    elem.appendChild(child)

proc insert(box, value, current: Element): Element =
  ## Inserts a single widget. Replaces the old widget if possible
  if current == nil:
    box.add(value)
  else:
    current.replaceWith(value)
  result = value

proc insert(box: Element, value, current: seq[Element], marker: Element): seq[Element] =
  ## Inserts a list of widgets.
  ## Inserts them after `marker`
  # TODO: Add reconcilation via keys
  for old in current:
    old.remove()
  var sibling = marker
  for new in value:
    discard sibling.after(new)
    sibling = new
    result &= new

proc insert[T: Element | seq[Element]](box: Element, value: Accessor[T],
                                               current: T = default(T), prev: Accessor[Element] = nil): Accessor[Element] =
  ## Top level insert that every widget gets called with.
  ## This handle reinserting the wiWindowWidgetdget if it gets updated.
  ## Always returns a GtkWidget. For lists this returns the item at the end
  var current = when T is seq: seq[Element](current) else: Element(current)
  createEffect do ():
    when T is seq:
      current = box.insert(value(), current, if prev != nil: prev() else: nil)
    else:
      current = box.insert(value(), current)

  return proc (): Element =
    when T is seq:
      if current.len == 0:
        return prev()
      current[^1]
    else:
      current

proc registerEvent(elem: Element, name: cstring, callback: proc (ev: Event)) =
  elem.addEventListener(name, callback)

  onCleanup do ():
    elem.removeEventListener(name, callback)

proc accessorProc(body: NimNode, returnType = ident"auto"): NimNode =
  newProc(
    params=[returnType],
    body=body
  )

proc wrapMemo(x: NimNode, returnType = ident"auto"): NimNode =
  newCall("createMemo", if x.kind == nnkProcDef: x else: accessorProc(x, returnType))

proc elemMemo(x: NimNode): NimNode =
  wrapMemo(x, ident"Element")


template nilElement(): NimNode = newCall(ident"Element", newNilLit())

# TODO: Do a two stage process like owlkettle. Should simplify the DSL from actual GUI construction
# and mean that its easier to add other renderers (Like HTML)

#[

Rewrites that need to get done. Memoisation is handled by the site that constructs the widget

Components
==========

```
Button(foo):
  bar = "test"
```
into
```
let elem = block:
  let e = Button(foo) # Args are passed
  # Properties are rewritten into effects
  createEffect do ():
    e.bar = "test"
```

If Expressions
==============

```
if something():
  Foo()
elif somethingElse():
  Bar()
```
into
```
let elem = block:
  if something():
    # Build Foo component
  elif somethingElse():
    # Build Bar component
  else:
    GtkWidget(nil) # We always need to return something
```

For Loops
=========

```
for i in 0..<count():
  Foo()
```
into
```
let items = block:
  var result: seq[GtkWidget]
  proc builder(x: i): Element =
    # build Foo
  for i in 0..<count():
    result &= builder(i)
  result
```
The proc means the loop variable is properly captured (So that semantics operate how you expect)
and also solves the issue with not being able to capture lents. This also paves the way for wrapping
each item in an `initRoot` so that can we key arrays
]#

proc processComp(x: NimNode): NimNode
proc processIf(x: NimNode): NimNode
proc processLoop(x: NimNode): NimNode

proc processNode(x: NimNode): NimNode =
  case x.kind
  of nnkIfStmt:
    x.processIf()
  of nnkCall:
    x.processComp()
  of nnkForStmt, nnkWhileStmt:
    x.processLoop()
  else:
    "Unexpected statement".error(x)


proc processIf(x: NimNode): NimNode =
  let ifStmt = nnkIfStmt.newTree()
  for branch in x:
    let rootCall = branch[^1][0].processNode()
    branch[^1] = rootCall
    ifStmt &= branch
  # Make sure its an expression
  if ifStmt[^1].kind != nnkElse:
    ifStmt &= nnkElse.newTree(nilElement())
  result = ifStmt

proc tryAdd(items: var seq[Element], widget: Element) =
  ## Only adds a widget if it isn't nil
  if widget != nil:
    items.add(widget)

proc findLoopVars(x: NimNode): seq[NimNode] =
  ## Returns a list of NimNodes that are variables in a loop
  case x.kind
  of nnkIdent:
    result &= x
  else:
    # TODO: Add proper checks before this explodes in our face
    for child in x:
      result &= findLoopVars(x)

proc processLoop(x: NimNode): NimNode =
  let
    itemsList = ident"items"
    loop = x
  let
    vars = findLoopVars(x[0])
    builderProc = genSym(nskProc, "builder")
    body = loop[^1][0].processNode().newStmtList()
  # Build the proc that will get called each loop
    builder = newProc(builderProc, @[
      ident"Element"
    ] & vars.mapIt(newIdentDefs(it, ident("typeof").newCall(it))), body = body)
  result = newStmtList()

  result &= nnkVarSection.newTree(
    nnkIdentDefs.newTree(itemsList, nnkBracketExpr.newTree(ident"seq", ident"Element"), newEmptyNode())
  )
  # Make the body just add items into the result
  loop[^1] = newStmtList(builder, newCall("tryAdd", itemsList, builderProc.newCall(vars)))
  result &= loop
  result &= itemsList

proc processComp(x: NimNode): NimNode =
  x.expectKind(nnkCall)
  # Check if we are creating a builtin element or a custom component
  # TODO: Compare style insensitive
  # Generate the inital call
  let init = newCall(x[0])
  var refVar: NimNode = nil
  # Pass args
  for arg in x[1..^1]:
    if arg.kind == nnkStmtList: break # This is the child
    if arg.kind == nnkRefTy:
      refVar = arg[0]
    else:
      init &= arg
  # Node that will return the component
  let
    widget = genSym(nskLet, "widget")
    compGen = newStmtList(newLetStmt(widget, init)) # TODO: Wrap in blockstmt
  # Now look through the children to find extra properties/event handlers.
  # Also store the nodes that we need to process after
  var
    children: seq[NimNode] # Child nodes to create after
    events: seq[tuple[name: string, handler: NimNode]]
  if x[^1].kind == nnkStmtList:
    for child in x[^1]:
      case child.kind
      of nnkProcDef: # Event handler
        let signalName = child.name.strVal.newLit()
        compGen &= newCall(ident"registerEvent", widget, signalName, newProc(body=child.body, params=[newEmptyNode(), nnkIdentDefs.newTree(ident"ev", ident"Event", newEmptyNode())]))
      of nnkAsgn: # Extra property
        # In future, this would just get added to the call
        let field = newDotExpr(widget, child[0])
        let effectBody = nnkAsgn.newTree(field, child[1])
        # Wrap the assignment in a createEffect
        compGen &= newCall(ident"createEffect", newProc(body=effectBody))
      of nnkIfStmt, nnkForStmt, nnkCall: # Other supported nodes
        children &= child
      else:
        discard processNode(child)

  # Process any children that need to get added
  let
    # We need to store the last widget seen has a "marker" for
    # loops so that they know where to start inserting items
    lastWidget = genSym(nskVar, "lastWidget")
  compGen &= nnkVarSection.newTree(nnkIdentDefs.newTree(lastWidget, bindSym"ElementMemo", elemMemo(widget)))
  for child in children:
    let body = child.processNode().wrapMemo(ident"auto")
    compGen &= nnkAsgn.newTree(lastWidget, newCall(ident"insert", widget, body, nnkExprEqExpr.newTree(ident"prev", lastWidget)))

  if refVar != nil:
    compGen &= nnkAsgn.newTree(refVar, widget)
  compGen &= widget
  result = "Element".ident().newCall(compGen)

macro gui(body: untyped): Element =
  result = processNode(body[0])
  echo result.toStrLit


when isMainModule:
  import std/[jsfetch, strformat, json, options]

  type
    Show = object
      Title: string
      Poster: string
      Plot: string

  proc search(text: cstring): Future[Show] {.async.} =
    let res = fetch(cstring fmt"https://omdbapi.com?apikey={key}&t={text}").await().text()
    let json = res.await().`$`.parseJson()
    if "Response" notin json:
      return json.to(Show)

  proc debounce(body: proc): proc (time: int) =
    var timeout: TimeOut
    let performTimout = proc (time: int) =
      clearTimeout(timeout)
      timeout = setTimeout(cast[proc()](body), time)
    performTimout


  proc App(): Element =
    let
      (show, setShow)= createSignal(none(Show))
      (searchString, setSearchString) = createSignal("")
    var input: Element
    let makeRequest = debounce() do () {.async.}:
      echo input.value
      input.value.search().await().some().setShow()

    return gui:
      tdiv:
        input(ref input):
          proc click() =
            makeRequest(1000)
        if show().isSome():
          text(show().get().Title)

  discard document.getElementById("root").insert(App)
