import std/[macros, strformat, dom, macrocache, asyncjs, sequtils]
import ./signal, ./domextras

type ElementMemo = Accessor[Element]

const builtinElements = CacheTable"fogair.elements"

macro registerElement(name: static[string], kind: typedesc): untyped =
  builtinElements[name] = kind
  # Return a proc which will create it
  let id = ident name
  result = quote do:
    # Saved 2kb by using templates. Seems Nim's codegen
    # doesn't play well with tersers mangler
    proc `id`*(): `kind` =
      `kind`(document.createElement(when `name` == "tdiv": "div" else: `name`))

# Basic elements
registerElement("tdiv", BaseElement)
registerElement("span", BaseElement)
registerElement("button", ButtonElement)
registerElement("nav", ButtonElement)
registerElement("ul", ButtonElement)
registerElement("ol", ButtonElement)
registerElement("li", ButtonElement)
registerElement("a", AElement)
registerElement("img", ImgElement)
registerElement("p", BaseElement)
# Form elements
registerElement("input", InputElement)
registerElement("select", BaseElement)
registerElement("option", OptionElement)

# Textual elements
registerElement("h1", BaseElement)
registerElement("h2", BaseElement)
registerElement("h3", BaseElement)
registerElement("h4", BaseElement)
registerElement("h5", BaseElement)
registerElement("strong", BaseElement)

proc isBuiltIn(name: string | NimNode): bool =
  ## Returns true if the name matches a built in element
  for key, _ in builtinElements:
    if key.eqIdent(name): return true

proc text*(val: string): Element =
  Element(document.createTextNode(val))

proc text*(val: Accessor[string]): Element =
  result = text(val())
  createEffect do ():
    result.innerText = cstring(val())

proc add(elem: Element, child: Element) =
  if child != nil:
    elem.appendChild(child)

macro jsHandler*(handler: typedesc[proc]): typedesc =
  ## Helper to convert a handler into a conjunction of possible handlers.
  ## Use this to make handlers have the same ergonomics like in JS
  # First build the list of different procs
  var
    options: seq[NimNode]
    currProc = nnkProcTy.newTree(nnkFormalParams.newTree(handler.params[0]), newEmptyNode())
  options &= currProc
  for identDef in handler.params[1 .. ^1]:
    let kind = identDef[^2]
    for param in identDef[0 ..< ^2]:
      let copy = currProc.copy()
      copy.params &= newIdentDefs(param, kind)
      options &= copy
  # Now build a list of everything or'd together
  result = options[0]
  for option in options[1 .. ^1]:
    result = nnkPar.newTree(nnkInfix.newTree(ident"or", result, option))

proc insert*(box, value, current: Element): Element =
  ## Inserts a single widget. Replaces the old widget if possible
  if current == nil:
    box.add(value)
  else:
    current.replaceWith(value)
  result = value

proc insert*(box, value: Element, prev: Accessor[Element]): Element =
  box.insert(value, nil)

proc remove*(child: Node) {.importcpp.}
proc insert*(box: Element, value, current: seq[Element], marker: Element): seq[Element] =
  ## Inserts a list of widgets.
  ## Inserts them after `marker`
  # TODO: Add reconcilation via keys
  for old in current:
    old.remove()
  if marker == nil:
    for new in value:
      box.appendChild(new)
      result &= new
  else:
    var sibling = marker
    for new in value:
      discard sibling.after(new)
      sibling = new
      result &= new

proc insert*[T: Element | seq[Element]](box: Element, value: Accessor[T],
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

# ???? Why doesn't it allow the same???

proc registerEvent*(elem: EventTarget, name: cstring, callback: (proc ())) =
  elem.addEventListener(name, cast[proc (ev: Event)](callback))

  onCleanup do ():
    elem.removeEventListener(name, cast[proc (ev: Event)](callback))

proc registerEvent*[E: Event](elem: EventTarget, name: cstring, callback: (proc (ev: E))) =
  elem.addEventListener(name, cast[proc (ev: Event)](callback))

  onCleanup do ():
    elem.removeEventListener(name, cast[proc (ev: Event)](callback))

proc accessorProc(body: NimNode, returnType = ident"auto"): NimNode =
  newProc(
    params=[returnType],
    body=body
  )

proc wrapMemo(x: NimNode, returnType = ident"auto"): NimNode =
  newCall("createMemo", if x.kind in {nnkProcDef, nnkSym}: x else: accessorProc(x, returnType))

proc elemMemo(x: NimNode): NimNode =
  wrapMemo(x, ident"Element")


proc tryElideMemo(x: NimNode): NimNode =
  ## Checks if the body reads a signal. If it doesn't
  ## then it removes the `createMemo` call.
  ## This removes the overhead of the memo and also inlines the body so removes the closure
  # Generate the call that gets passed to the memo.
  # We need to copy the compiler or the compiler will error during lambda lifting (It syms the proc to be a closure, then gets confused when we inline it)
  let innerCall = if x.kind == nnkProcDef: x else: accessorProc(x.copy())
  result = newStmtList()
  let innerCallSym = genSym(nskLet, "innerCall")
  result &= newLetStmt(innerCallSym, innerCall)
  # If it does read a signal, then it needs to be wrapped in a memo.
  # Otherwise we can just pass the return value directly
  result &= nnkWhenStmt.newTree(
    nnkElifBranch.newTree(newCall(ident"performsRead", innerCallSym), wrapMemo(innerCallSym)),
    nnkElse.newTree(x)
  )


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

Case Expressions
================

```
case data():
of Foo: discard
of Bar: text("hello")
```
into
```
let elem = block
  case data()
  of Foo: nil # Need to return something
  of Bar: # Build text widget
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
proc processCase(x: NimNode): NimNode
proc processStmts(x: NimNode): NimNode

proc processNode(x: NimNode): NimNode =
  case x.kind
  of nnkIfStmt:
    x.processIf()
  of nnkCall, nnkCommand:
    x.processComp()
  of nnkForStmt, nnkWhileStmt:
    x.processLoop()
  of nnkCaseStmt:
    x.processCase()
  of nnkStmtList:
    # Compiler bug?
    #result = nnkStmtList.newTree()
    #for node in x:
    #  result &= node.processNode()
    #result
    x.processStmts()
  of nnkLetSection:
    x
  else:
    ("Unexpected statement: " & $x.kind).error(x)

proc processStmts(x: NimNode): NimNode =
  result = newStmtList()
  for node in x:
    result &= node.processNode()

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

proc tryAdd*(items: var seq[Element], widget: Element) =
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
    # This is so the closure stores the loop variable and makes it behave
    # as expected
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

proc processCase(x: NimNode): NimNode =
  x.expectKind(nnkCaseStmt)
  result = nnkCaseStmt.newTree(x[0])
  for branch in x[1..^1]: # Ignore first item
    let expr = branch[^1]
    if expr.kind == nnkStmtList and expr[0].kind == nnkDiscardStmt:
      # Discard could have side effects, so still call it but make it
      # into an expression that returns nil
      branch[^1] = newStmtList(expr[0], nilElement())
    else:
      let rootCall = branch[^1].processNode()
      branch[^1] = rootCall
    result &= branch

proc generateAsgn(widget, prop, value: NimNode): NimNode =
  ## Generates an assignment.
  ## Optimises static values to not be wrapped in an effect
  let field = newDotExpr(widget, prop)
  # Style we set with setAttribute.
  if prop.eqIdent("style"):
    result = newCall(ident"setAttribute", widget, newLit $prop, value)
  else:
    result = nnkAsgn.newTree(field, value)
  # Wrap the assignment in a createEffect if not a static value.
  # In future the createEffect should be smarter and track effects and then
  # optimise itself out if there are no effects in the body
  if value.kind notin nnkLiterals:
    result = newCall(ident"createEffect", newProc(body=result))

proc processComp(x: NimNode): NimNode =
  let init = newCall(x[0])
  # Check if this is a native HTML element.
  # Then we must add the properties to the body inside of the call
  let native = isBuiltIn(x[0])
  var
    refVar: NimNode = nil
    props: seq[NimNode]
  # Pass args
  for arg in x[1..^1]:
    if arg.kind == nnkStmtList: break # This is the child
    if arg.kind == nnkRefTy:
      refVar = arg[0]
    else:
      # TODO: Add error handling for native elements.
      # i.e. everything should be passed like prop=value
      props &= arg
  # Node that will return the component
  let
    widget = ident("widget")
    compGen = newStmtList(newLetStmt(widget, init))
  # Native elements need each property to be assigned
  # Non native elements need the props passed to the call
  if native:
    for prop in props:
      compGen &= generateAsgn(widget, prop[0], prop[1])
  else:
    init &= props
  # Now look through the children to find extra properties/event handlers.
  # Also store the nodes that we need to process after
  var
    children: seq[NimNode] # Child nodes to create after
    events: seq[tuple[name: string, handler: NimNode]]
    hasComplexStmt = false # Track any case, for, if, etc
  if x[^1].kind == nnkStmtList:
    for child in x[^1]:
      case child.kind
      of nnkProcDef: # Event handler
        let signalName = child.name.strVal.newLit()
        compGen &= child
        compGen &= newCall(ident"registerEvent", widget, newCall("cstring", signalName), child.name)
      of nnkAsgn: # Extra property
        compGen &= generateAsgn(widget, child[0], child[1])
      of nnkIfStmt, nnkForStmt, nnkCall, nnkCaseStmt: # Other supported nodes
        # TODO: Check if I pass lastWidget for if and case statements.
        # Since if they return nil, what do we replace with when not null???
        if child.kind in {nnkIfStmt, nnkForStmt, nnkCaseStmt}:
          hasComplexStmt = true
        children &= child
      else:
        # ???? Shouldn't I error here?
        discard processNode(child)

  # Process any children that need to get added
  if children.len > 0:
    let
      # We need to store the last widget seen has a "marker" for
      # loops so that they know where to start inserting items
      lastWidget = genSym(nskVar, "lastWidget")
    compGen.add quote do:
      var `lastWidget`: ElementMemo = nil
    for child in children:
      let body = if not hasComplexStmt:
          child.processNode().tryElideMemo()
        else:
          child.processNode().wrapMemo()
      let insertCall = newCall(ident"insert", widget, body, nnkExprEqExpr.newTree(ident"prev", lastWidget))
      if hasComplexStmt:
        compGen &= nnkAsgn.newTree(lastWidget, insertCall)
      else:
        compGen &= nnkDiscardStmt.newTree(insertCall)


  if refVar != nil:
    compGen &= nnkAsgn.newTree(refVar, widget)
  compGen &= widget
  # Sometimes the body is just a call. Optimise this into just the call
  if compGen.len == 2:
    echo compGen.treeRepr
    result = "Element".ident().newCall(compGen[0][0][2])
  else:
    result = "Element".ident().newCall(nnkBlockStmt.newTree(newEmptyNode(), compGen))

macro gui*(body: untyped): Element =
  ## TODO: Error if there are multiple elements
  result = processNode(body[0])
  echo result.toStrLit


when isMainModule:
  import std/[jsfetch, strformat, json, options]
  const key {.strdefine: "omdbKey".}: string = ""

  type
    Show = object
      Title: string
      Poster: string
      Plot: string

  proc search(text: cstring): Future[Option[Show]] {.async.} =
    let res = fetch(cstring fmt"https://omdbapi.com?apikey={key}&t={text}").await().text()
    let json = res.await().`$`.parseJson()
    if json["Response"].getStr() == "True":
      return some json.to(Show)
    else:
      # This gets around a compiler bug with it not properly setting the result.
      # So the code would be unsound since it would be returning null instead of none(Show)
      return none(Show)

  proc debounce(time: int, body: proc): proc () =
      ## Returns a proc that will get debounced if called multiple times
      var timeout: TimeOut
      let performTimout = proc () =
        clearTimeout(timeout)
        timeout = setTimeout(cast[proc()](body), time)
      performTimout

  type
    AsyncState = enum
      Nothing
      Loading
      Loaded
    AsyncSignal[T] = object
      case state: AsyncState
      of Nothing, Loading: discard
      of Loaded:
        data: T
  import std/jsconsole
  proc createFuture[T](): tuple[data: Accessor[AsyncSignal[T]], setter: Setter[Future[T]]] =
    let (data, setData) = createSignal(AsyncSignal[T](state: Nothing))
    let (future, setFuture) = createSignal[Future[T]](nil)
    createEffect() do ():
      let future = future()
      console.log(future)
      if future != nil:
        setData(AsyncSignal[T](state: Loading))
        discard future.then(
          onSuccess = proc (data: T) =
            setData(AsyncSignal[T](state: Loaded, data: data))
          ,onReject = proc (reason: Error) =
            echo "Error ", reason.message
        )
    return (data, setFuture)

  proc App(): Element =
    let
      (data, setData) = createFuture[Option[Show]]()
      (searchString, setSearchString) = createSignal("")
    var input: Element

    let makeRequest = debounce(1000) do ():
      input.value.search().setData()

    return gui:
      tdiv(class="test"):
        input(ref input):
          proc input() =
            makeRequest()
        case data().state
        of Nothing: discard
        of Loading:
          text("Loading...")
        of Loaded:
          let show = data().data
          if show.isSome():
            text(show.unsafeGet.Title)
          else:
            text("Not found")

  discard document.getElementById("root").insert(App)

export domextras
