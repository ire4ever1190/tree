import std/[macros, dom, macrocache, sequtils]
import ./signal, ./domextras


type ElementMemo = Accessor[Element]

const builtinElements = CacheTable"tree.elements"

macro registerElement*(name: static[string], kind: typedesc, elemName: static[string] = ""): untyped =
  ## Registers an internal element. You should't have to touch this unless you
  ## are adding a new element (Not a component)
  runnableExamples:
    type
      CustomElement {.importc.} = ref object of BaseElement
        customAttr: cstring

    registerElement("customElement", CustomElement, "custom-element")

    proc App(): Element =
      gui:
        customElement(customAttr="test")
  #==#
  builtinElements[name] = kind
  # Return a proc which will create it
  let id = ident name
  let elemNameStr = if elemName != "": elemName else: name
  result = quote do:
    # Saved 2kb by using templates. Seems Nim's codegen
    # doesn't play well with tersers mangler
    template `id`*(): `kind` =
      `kind`(document.createElement(`elemNameStr`))

# Basic elements
registerElement("tdiv", BaseElement, "div")
registerElement("span", BaseElement)
registerElement("button", ButtonElement)
registerElement("nav", ButtonElement)
registerElement("ul", ButtonElement)
registerElement("ol", ButtonElement)
registerElement("li", ButtonElement)
registerElement("a", AElement)
registerElement("img", ImgElement)
registerElement("fieldset", BaseElement)
registerElement("legend", BaseElement)
# Form elements
registerElement("input", InputElement)
registerElement("select", BaseElement)
registerElement("option", OptionElement)
registerElement("label", LabelElement)

# Textual elements
registerElement("p", BaseElement)
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


proc text*(val: cstring): Node =
  ## Creates a text node
  document.createTextNode(val)

proc text*(val: string): Node =
  text(val.cstring)

proc text*(val: Accessor[string]): Accessor[Node] {.effectsOf: val.} =
  ## Helper that takes in a string created from a signal
  let elem = text(val())
  createEffect do ():
    elem.innerText = cstring(val())
  # Remove this in future for optimisation.
  # Issue is case statements with just string branches get optimised
  # into a single node which causes problems with the case expression
  # expecting a memo to be returned
  proc (): Node = elem


# To support any expression being in the tree we have these
# coerce calls to check if value can become an element and then
# perform implicit conversion
template coerceIntoElement(val: Node): Element {.callsite.} =
  ## For explicit conversion of Node into Element
  when val is Element: val else: Element(val)

template coerceIntoElement(val: Accessor[Node]): Accessor[Element] =
  cast[Accessor[Element]](val)

template coerceIntoElement[T: Element | seq[Element]](val: Accessor[T]): Accessor[T] =
  val

template coerceIntoElement*(val: string | Accessor[string]): untyped =
  ## Template for implicit conversion of string into Element
  coerceIntoElement(text(val))

template coerceIntoElement[T: void](val: T) =
  ## Doesn't convert into an Element, but allows support for
  ## statements within the GUI.
  ## e.g. echo "test", let x = 8

template coerceIntoElement(val: typeof(nil)): Element = Element(nil)

template checkExpr*(val: typed): untyped {.callsite.} =
  ## Checks that the expression given can be converted into an element.
  ## This is to provide better messages than a bunch of overloads
  bind coerceIntoElement
  when not compiles(coerceIntoElement(val)):
    {.error: $type(val) & " can't be converted into an element".}
  else:
    coerceIntoElement(val)


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
  box.insert(value, Element(nil))

proc remove*(child: Node) {.importcpp.}

proc insert*(box: Element, value, current: seq[Element], marker: Element): seq[Element] =
  ## Inserts a list of widgets.
  ## Inserts them after `marker`
  # TODO: Add reconcilation via keys
  # TODO: Use append/prepend with multiple items
  for old in current:
    old.remove()
  if marker == nil:
    for new in value:
      box.appendChild(new)
      result &= new
  elif marker == box: # parent is sentinal for prepending the element
    for new in value:
      box.prepend(new)
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
  var current = when T is seq: current else: current
  createEffect do ():
    when T is seq:
      current = box.insert(value(), current, if prev != nil: prev() else: nil)
    else:
      current = box.insert(value(), current)
  # Return an accessor that returns the tip element
  # Used by for loops to know what element to append to
  return proc (): Element =
    # If the current element doesn't exist then we need to
    # return what came before
    if (when T is seq: current.len == 0 else: current == nil):
      #
      if prev == nil:
        return box
      return prev()
    when T is seq:
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

proc tryElideMemo(x: NimNode): NimNode =
  ## Checks if the body reads a signal. If it doesn't
  ## then it removes the `createMemo` call.
  ## This removes the overhead of the memo and also inlines the body so removes the closure
  # Generate the call that gets passed to the memo.
  # We need to copy the compiler or the compiler will error during lambda lifting (It syms the proc to be a closure, then gets confused when we inline it)
  let innerCall = if x.kind == nnkProcDef: x else: accessorProc(x.copy())
  result = newStmtList()
  # Make it be an actual function instead of a variable.
  # This way it can have DCE
  let innerCallSym = genSym(nskProc, "innerCall")
  innerCall.name = innerCallSym
  result &= innerCall
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

Try/Except
==========
Finally is not supported since it doesn't make sense
```
try:
  # Some code
except:
  # Error code
```
into
```
let item = block:
  let (curr, setCurr) = createSignal[Element](nil)
  try:
    setCurr:
      # Some code
  except:
    setCurr:
      # Error code
  curr()
```
This will get wrapped in a createMemo. Reason for the signal is that the except block might get called
afterwards (Maybe some handler raises an exception)
]#

proc processComp(x: NimNode): NimNode
proc processCondtional(x: NimNode): NimNode
proc processLoop(x: NimNode): NimNode
proc processCase(x: NimNode): NimNode
proc processStmts(x: NimNode): NimNode
proc processTryExcept(x: NimNode): NimNode

proc processNode(x: NimNode): NimNode =
  case x.kind
  of nnkIfStmt, nnkWhenStmt:
    x.processCondtional()
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
  of nnkTryStmt:
    x.processTryExcept()
  else:
    # Everything else is an expression, so we must
    # check its an Element
    newCall("checkExpr", x)

proc processStmts(x: NimNode): NimNode =
  result = newStmtList()
  for node in x:
    result &= node.processNode()

proc processCondtional(x: NimNode): NimNode =
  ## Handles `if` and `when` expressions
  assert x.kind in {nnkIfStmt, nnkWhenStmt}
  result = x.kind.newTree()
  for branch in x:
    let rootCall = branch[^1][0].processNode()
    branch[^1] = rootCall
    result &= branch
  # Must always be an expression so we must
  # add an else branch if it doesnt exist
  if result[^1].kind != nnkElse:
    result &= nnkElse.newTree(nilElement())

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
    branch[^1] = branch[^1].processNode()
    result &= branch
  # We don't add an else branch since that would break safety
  # of checking all cases

proc processTryExcept(x: NimNode): NimNode =
  x.expectKind(nnkTryStmt)
  result = x
  result[0] = result[0].processNode()
  for i in 1 ..< x.len:
    result[i][^1] = result[i][^1].processNode()

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
  widget.copyLineInfo(x)
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
      else: # Anything else will get processed and added later
        # TODO: Check if I pass lastWidget for if and case statements.
        # Since if they return nil, what do we replace with when not null???
        if child.kind in {nnkIfStmt, nnkForStmt, nnkCaseStmt, nnkTryStmt}:
          hasComplexStmt = true
        children &= child

  # Process any children that need to get added
  if children.len > 0:
    let
      # We need to store the last widget seen has a "marker" for
      # loops so that they know where to start inserting items
      lastWidget = genSym(nskVar, "lastWidget")
    compGen.add quote do:
      var `lastWidget`: ElementMemo = nil
    for child in children:
      let
        processed = child.processNode()
        # TODO: Why don't I optimise complex statements?
        body = if not hasComplexStmt: processed.tryElideMemo()
               else: processed.wrapMemo()
      let insertCall = newCall(ident"insert", widget, body, nnkExprEqExpr.newTree(ident"prev", lastWidget))
      if hasComplexStmt:
        compGen &= nnkAsgn.newTree(lastWidget, insertCall)
      else:
        compGen &= nnkDiscardStmt.newTree(insertCall)


  if refVar != nil:
    compGen &= nnkAsgn.newTree(refVar, widget)
  compGen &= widget
  # Sometimes the body is just a call. Optimise this into just the call.
  # Noticed that the block statement added some weirdness in the codegen
  if compGen.len == 2:
    result = compGen[0][0][2]
  else:
    result = nnkBlockStmt.newTree(newEmptyNode(), compGen)
  # Coerce the return into an element
  result = newCall("checkExpr", result)

macro gui*(body: untyped): Element =
  ## TODO: Error if there are multiple elements
  result = processNode(body[0])
  when defined(debugTreeGui):
    echo result.toStrLit

proc renderTo*(component: proc (): Element, id: string) =
  ## Renders the application to an element with `id`
  discard document.getElementById(id).insert(component)

export domextras
export dom
