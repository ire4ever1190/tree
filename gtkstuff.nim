import owlkettle/bindings/[adw, gtk]
import std/[macros, strformat]
import signal

{.push importc, cdecl.}
proc gtk_button_set_label(button: GtkWidget, label: cstring)
{.pop.}

let app = gtk_application_new(cstring"dev.leahy.example", G_APPLICATION_FLAGS_NONE);

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
  gtk_box_append(box.GtkWidget, widget.GtkWidget)

proc add[T](window: WindowWidget, widget: T) =
  gtk_window_set_child(window.GtkWidget, widget.GtkWidget)

proc replace[T](box: BoxWidget, new, old: T) =
  ## Shitty replace function. Basically append the new widget
  ## after the old one and then remove the old one. Shitty
  ## since it means we are looping through the widgets twice
  let widget = box.GtkWidget
  if new.pointer != nil:
    widget.gtkBoxInsertChildAfter(new, old)
  widget.gtkBoxRemove(old)

proc replace[T](box: WindowWidget, new, old: T) =
  box.add(new)

proc insert[T: not proc](box: BoxWidget | WindowWidget, value, current: T): T =
  if current.pointer == nil:
    box.add(value)
  else:
    box.replace(value, current)
  result = value

proc insert[T](box: BoxWidget | WindowWidget, value: Accessor[T], current: T): Accessor[T] =
  var current = current
  createEffect do ():
    current = box.insert(value(), current)

  return proc (): T = current

macro generateProcType(x: typedesc): type =
  let tupleType = x.getTypeImpl()[1]
  echo tupleType.treeRepr
  var params = nnkFormalParams.newTree()
  params &= newEmptyNode()
  for field in tupleType:
    params &= newIdentDefs(ident $field[0], ident $field[1])
  # Add the env variable
  params &= newIdentDefs(ident "env", ident "pointer")
  result = nnkProcTy.newTree(params, nnkPragma.newTree(ident"nimcall"))

proc callClosure[T](widget: pointer, data: ClosureProc) {.cdecl.} =
  let info = cast[ClosureProc](data)
  cast[T.generateProcType()](info.prc)(info.env)

proc wrapClosure(prc: proc): ClosureProc =
  ClosureProc(prc: cast[ClosureProc.prc](prc.rawProc()), env: prc.rawEnv())

proc registerEvent(widget: GtkWidget, name: cstring, callback: proc ()) =
  let data = wrapClosure(callback)
  GCRef(data)
  let callback = callClosure[tuple[]]
  let id = widget.gSignalConnect(name, callback, cast[pointer](data))

  onCleanup do ():
    # Unregister the handler, and let GC handle the closure
    # widget.pointer.gSignalHandlerDisconnect(id)
    GCUnref(data)


proc processGUI(x: NimNode): NimNode =
  x.expectKind(nnkCall)
  # See which element to create
  # TODO: Have better system than this
  let init = newCall(x[0])
  # Pass args
  for arg in x[1..^1]:
    if arg.kind == nnkStmtList: break # This is the child
    init &= arg

  let widgetName = genSym(nskLet, "widget")
  result = newStmtList()
  # Start the widget creation
  result &= newLetStmt(widgetName, newCall(ident"initRoot", newProc(params=[ident"auto"], body=init)))
  if x[^1].kind == nnkStmtList:
    # Create children and register any events
    for child in x[^1]:
      echo child.kind
      case child.kind
      of nnkProcDef:
        # Register event for procs
        let signalName = child.name.strVal
        result &= newCall(ident"registerEvent", newCall("GtkWidget", widgetName), newLit signalName, newProc(body=child.body))
      of nnkCall:
        # Create child if its a call
        let childName = genSym(nskLet, "child")
        result &= newLetStmt(childName, processGUI(child))
        result &= nnkDiscardStmt.newTree(newCall(ident"insert", widgetName, newCall("GtkWidget", childName), "GtkWidget".newCall(newNilLit())))
      of nnkAsgn:
        # Set a reactive property
        # TODO: Find better way of dealing with nonreactive/reactive and allow both
        # to be declared inline. Will need better tag tracking for that though
        # Check this isn't setting a ref
        let field = newDotExpr(widgetName, child[0])
        let effectBody = nnkAsgn.newTree(field, child[1])
        # Wrap the assignment in a createEffect
        result &= newCall(ident"createEffect", newProc(body=effectBody))
      of nnkIfStmt:
        # Build it into a function which `insert` can handle
        # We also need to make sure that each body gets processed
        let ifStmt = nnkIfStmt.newTree()
        for branch in child:
          let rootCall = newCall(ident"initRoot", newProc(params=[ident"GtkWidget"], body=branch[^1][0].processGUI()), newLit"Some root")
          branch[^1] = rootCall
          ifStmt &= branch
        # Make sure its an expression
        if ifStmt[^1].kind != nnkElse:
          ifStmt &= nnkElse.newTree("GtkWidget".newCall(newNilLit()))
        result &= nnkDiscardStmt.newTree(newCall(ident"insert", widgetName, newCall("createMemo", newProc(params=[ident"GtkWidget"],body=ifStmt)), "GtkWidget".newCall(newNilLit())))
      else:
        "Unknown node".error(child)
  # Return the child
  result &= widgetName


macro gui(body: untyped): GtkWidget =
  let widget = processGUI(body[0])
  echo widget.toStrLit
  newCall(ident"GtkWidget", widget)


proc Counter(): GtkWidget =
  onCleanup do ():
    echo "Cleaning widget"

  let (count, setCount) = createSignal(0)
  return gui:
    Box(Vertical, 0):
      Button(text="Click me"):
        proc clicked() =
          setCount(count() + 1)
      Label():
        text = fmt"Count is {count()}"

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

