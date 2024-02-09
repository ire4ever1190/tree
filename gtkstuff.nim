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

  Button = distinct GtkWidget
  Box = distinct GtkWidget
  Label = distinct GtkWidget

  Orientation = enum
    Vertical
    Horizontal

proc newButton(text: cstring = ""): Button =
  if text != "":
    gtk_button_new_with_label(text).Button
  else:
    gtk_button_new().Button

proc newBox(orient: Orientation, spacing: cint = 0): Box =
  const mapping: array[Orientation, GtkOrientation] = [GTK_ORIENTATION_VERTICAL, GTK_ORIENTATION_HORIZONTAL]
  gtk_box_new(mapping[orient], spacing).Box

proc newLabel(text: cstring = ""): Label = gtk_label_new(text).Label
proc `text=`(label: Label, text: string) = gtk_label_set_text(label.GtkWidget, text.cstring)


proc add[T](box: Box, widget: T) =
  gtk_box_append(box.GtkWidget, widget.GtkWidget)

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
  echo "Connecting signal"
  let id = widget.gSignalConnect(name, callback, cast[pointer](data))

  onCleanup do ():
    # Unregister the handler, and let GC handle the closure
    widget.pointer.gSignalHandlerDisconnect(id)
    GCUnref(data)


proc processGUI(x: NimNode): NimNode =
  x.expectKind(nnkCall)
  # See which element to create
  # TODO: Have better system than this
  let init = newCall(ident "new" & x[0].strVal)
  # Pass args
  for arg in x[1..^1]:
    if arg.kind == nnkStmtList: break # This is the child
    init &= arg

  let widgetName = genSym(nskLet, "widget")
  result = newStmtList()
  # Start the widget creation
  result &= newLetStmt(widgetName, init)
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
        result &= newCall(ident"add", widgetName, childName)
      of nnkAsgn:
        # Set a reactive property
        # TODO: Find better way of dealing with nonreactive/reactive and allow both
        # to be declared inline. Will need better tag tracking for that though

        let field = newDotExpr(widgetName, child[0])
        let effectBody = nnkAsgn.newTree(field, child[1])
        # Wrap the assignment in a createEffect
        result &= newCall(ident"createEffect", newProc(body=effectBody))
      else:
        "Unknown node".error(child)
  # Return the child
  result &= widgetName


macro gui(body: untyped): GtkWidget =
  let widget = processGUI(body[0])
  echo widget.toStrLit
  newCall(ident"GtkWidget", widget)

proc counter(): GtkWidget =
  let (count, setCount) = createSignal(0)

  return gui:
    Box(Vertical, 0):
      Button(text="Click me"):
        proc clicked() =
          setCount(count() + 1)
      Label():
        text = fmt"Count is {count()}"

proc activate(app: G_APPLICATION, data: pointer) =
  let window = gtk_window_new(GTK_WINDOW_TOPLEVEL)
  gtk_window_set_title(window, "Window");
  gtk_window_set_default_size(window, 200, 200);
  gtk_window_present(window);
  gtk_application_add_window(app, window)

  gtk_window_set_child(window, counter())


discard g_signal_connect(app, "activate", activate, nil);
discard g_application_run(app)
g_object_unref(pointer(app))

