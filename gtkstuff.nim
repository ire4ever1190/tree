import owlkettle/bindings/[adw, gtk]
import std/[macros, strformat]
import signal
import asyncdispatch

{.push importc, cdecl.}
proc gtk_button_set_label(button: GtkWidget, label: cstring)
proc g_timeout_add(interval: cuint, function: proc (): bool {.cdecl.}, data: pointer)
{.pop.}



let app = gtk_application_new(cstring"dev.leahy.example", G_APPLICATION_FLAGS_NONE);

proc callDispatcher(): bool {.cdecl.} =
  if hasPendingOperations():
    poll(0)
  return true

g_timeout_add(400.cuint, callDispatcher, nil)

type
  ClosureProc = ref object
    prc: pointer
    env: pointer

  BtnWidget = distinct GtkWidget
  BoxWidget = distinct GtkWidget
  LblWidget = distinct GtkWidget
  WindowWidget = distinct GtkWidget

  Orientation = enum
    Vertical
    Horizontal

proc Button(text: cstring = ""): BtnWidget =
  if text != "":
    gtk_button_new_with_label(text).BtnWidget
  else:
    gtk_button_new().BtnWidget
proc `text=`(btn: BtnWidget, text: string) =
  gtk_button_set_label(btn.GtkWidget, text.cstring)

proc Box(orient: Orientation, spacing: cint = 0): BoxWidget =
  const mapping: array[Orientation, GtkOrientation] = [GTK_ORIENTATION_VERTICAL, GTK_ORIENTATION_HORIZONTAL]
  gtk_box_new(mapping[orient], spacing).BoxWidget

proc Window(): WindowWidget =
  gtk_window_new(GTK_WINDOW_TOPLEVEL).WindowWidget()

proc `defaultSize=`(window: WindowWidget, size: tuple[width: int, height: int]) =
  window.GtkWidget.gtk_window_set_default_size(size.width.cint, size.height.cint)
proc `title=`(window: WindowWidget, title: string) =
  gtk_window_set_title(window.GtkWidget, title.cstring)


proc Label(text: cstring = ""): LblWidget = gtk_label_new(text).LblWidget
proc `text=`(label: LblWidget, text: string) = gtk_label_set_text(label.GtkWidget, text.cstring)


proc add[T](box: BoxWidget, widget: T) =
  if widget.pointer != nil:
    gtk_box_append(box.GtkWidget, widget.GtkWidget)

proc add[T](window: WindowWidget, widget: T) =
  gtk_window_set_child(window.GtkWidget, widget.GtkWidget)

proc addAfter[T](box: BoxWidget, widget, after: T) =
  gtkBoxInsertChildAfter(box.GtkWidget, widget.GtkWidget, after.GtkWidget)

proc remove[T](box: BoxWidget, child: T) =
  box.GtkWidget.gtkBoxRemove(child)

proc replace[T](box: BoxWidget, new, old: T) =
  ## Shitty replace function. Basically append the new widget
  ## after the old one and then remove the old one. Shitty
  ## since it means we are looping through the widgets twice
  if new.pointer != nil:
    box.addAfter(new, old)
  box.remove(old)

proc replace[T](box: WindowWidget, new, old: T) =
  box.add(new)

proc insert[T: not proc](box: BoxWidget | WindowWidget, value, current: T): T =
  ## Inserts a single widget. Replaces the old widget if possible
  if current.pointer == nil:
    box.add(value)
  else:
    box.replace(value, current)
  result = value

proc insert[T](box: BoxWidget | WindowWidget, value, current: seq[T], marker: GtkWidget): seq[T] =
  ## Inserts a list of widgets.
  ## Inserts them after `marker`
  # TODO: Add reconcilation via keys
  for old in current:
    box.remove(old)
  var sibling = marker
  for new in value:
    box.addAfter(new, sibling)
    sibling = new
    result &= new

proc insert[T](box: BoxWidget | WindowWidget, value: Accessor[T], current: T = default(T), prev: Accessor[GtkWidget] = nil): Accessor[GtkWidget] =
  ## Top level insert that every widget gets called with.
  ## This handle reinserting the widget if it gets updated.
  ## Always returns a GtkWidget. For lists this returns the item at the end
  var current = current
  createEffect do ():
    when T is seq:
      current = box.insert(value(), current, prev())
    else:
      current = box.insert(value(), current)

  return proc (): GtkWidget =
    when T is seq:
      current[^1]
    else:
      current

proc callIt(widget, data: pointer) {.cdecl.} =
  let prc = cast[ref proc ()](data)
  prc[]()

proc registerEvent(widget: GtkWidget, name: cstring, callback: proc ()) =
  let data = new typeof(callback)
  GCRef(data)
  data[] = callback
  let id = widget.gSignalConnect(name, callIt, cast[pointer](data))

  onCleanup do ():
    echo "Cleaning"
    # Unregister the handler, and let GC handle the closure
    widget.pointer.gSignalHandlerDisconnect(id)
    GCUnref(data)

proc toWidget(x: NimNode): NimNode = newCall(ident"GtkWidget", x)

proc accessorProc(body: NimNode, returnType = ident"auto"): NimNode =
  newProc(
    params=[returnType],
    body=body
  )

proc wrapMemo(x: NimNode, returnType = ident"auto"): NimNode =
  newCall("createMemo", if x.kind == nnkProcDef: x else: accessorProc(x, returnType))

type WidgetMemo = Accessor[GtkWidget]

template nilWidget(): NimNode = newCall(ident"GtkWidget", newNilLit())

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
  for i in 0..<count():
    result &= # Build Foo
  result

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
    ifStmt &= nnkElse.newTree("GtkWidget".newCall(newNilLit()))
  result = ifStmt

proc tryAdd(items: var seq[GtkWidget], widget: GtkWidget) =
  ## Only adds a widget if it isn't nil
  if pointer(widget) != nil:
    items.add(widget)

proc processLoop(x: NimNode): NimNode =
  let
    itemsList = ident"items"
    loop = x
  result = newStmtList()
  result &= nnkVarSection.newTree(
    nnkIdentDefs.newTree(itemsList, nnkBracketExpr.newTree(ident"seq", ident"GtkWidget"), newEmptyNode())
  )
  # Make the body just add items into the result
  loop[^1] = newStmtList(newCall("tryAdd", itemsList, "GtkWidget".newCall(processNode(loop[^1][0]))))
  result &= loop
  result &= itemsList

proc processComp(x: NimNode): NimNode =
  x.expectKind(nnkCall)
  # Generate the inital call
  let init = newCall(x[0])
  # Pass args
  for arg in x[1..^1]:
    if arg.kind == nnkStmtList: break # This is the child
    init &= arg
  # Node that will return the component
  let
    widget = ident"widget"
    rawWidget = newCall("GtkWidget", widget)
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
        compGen &= newCall(ident"registerEvent", rawWidget, signalName, newProc(body=child.body))
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
    lastWidget = ident"lastWidget"
  compGen &= nnkVarSection.newTree(nnkIdentDefs.newTree(lastWidget, bindSym"WidgetMemo", newEmptyNode()))
  for child in children:
    let body = child.processNode().wrapMemo(ident"auto")
    compGen &= nnkAsgn.newTree(lastWidget, newCall(ident"insert", widget, body, nnkExprEqExpr.newTree(ident"prev", lastWidget)))

  compGen &= rawWidget
  result = compGen

macro gui(body: untyped): GtkWidget =
  let widget = processNode(body[0])
  echo widget.toStrLit
  newCall(ident"GtkWidget", widget)

when false:
  proc Buggon(i: int): GtkWidget =
    onCleanup do ():
      echo "Cleaning buggy"
    result = gui:
      Label($i)


  proc Counter(): GtkWidget =
    var (text, setText) = createSignal("Nothing")

    let (count, setCount) = createSignal(0)
    return gui:
      Box(Vertical, 0):
        Button(text="Click me"):
          proc clicked() =
            setCount(count() + 1)
        for i in 0..<count() {.key: i.}:
          Buggon(i)

  proc App(): GtkWidget =
    let (show, setShow) = createSignal(true)
    return gui:
      Window:
        defaultSize = (200, 200)
        Box(Vertical, 10):
          Button(text="Show/hide"):
            proc clicked() =
              setShow(not show())
          if show():
            Counter()


proc Test(): GtkWidget =
  onCleanup do ():
    echo "Cleaning test"
  return gui:
    Label("Hello")

proc App(): GtkWidget =
  let (show, setShow) = createSignal(false)
  let (count, setCount) = createSignal(0)

  return gui:
    Window:
      defaultSize = (200, 200)
      Box(Vertical, 10):
        Button():
          proc clicked() =
            setShow(not show())
          text = "Show/Hide"
        if show():
          Test()
        Button("Inc"):
          proc clicked() =
            setCount(count() + 1)
        for i in 0..<count():
          Label("Hello")

proc render(app: GApplication, window: GtkWidget) =
  gtk_window_present(window);
  gtk_application_add_window(app, window)

proc activate(app: G_APPLICATION, data: pointer) =
  # gtk_window_set_title(window, "Window");
  # gtk_window_set_default_size(window, 200, 200);
  app.render(App())

discard g_signal_connect(app, "activate", activate, nil);
discard g_application_run(app)
g_object_unref(pointer(app))

