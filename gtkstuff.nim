import owlkettle/bindings/[adw, gtk]

{.push importc, cdecl.}
proc gtk_button_set_label(button: GtkWidget, label: cstring)
{.pop.}

let app = gtk_application_new(cstring"dev.leahy.example", G_APPLICATION_FLAGS_NONE);

type
  Widget = ref object of RootObj
    internal: GtkWidget
    callbacks: seq[ClosureProc]

  ClosureProc = ref object
    prc: pointer
    env: pointer

  Container = ref object of Widget
    children: seq[Widget]

  Box = ref object of Widget

  Button = ref object of Widget

proc `label=`(button: Button, label: string) =
  button.internal.gtk_button_set_label(cstring label)

proc new[T: Button](_: T): T =
  Button(internal: gtk_button_new())


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


proc activate(app: G_APPLICATION, data: pointer) =
  let window = gtk_window_new(GTK_WINDOW_TOPLEVEL)
  gtk_window_set_title(window, "Window");
  gtk_window_set_default_size(window, 200, 200);
  gtk_window_present(window);
  gtk_application_add_window(app, window)

  let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)
  gtk_window_set_child(window, box)

  let button = gtk_button_new_with_label("Hello World")
  gtk_box_append(box, button)

  let btn = Button.new()

  let count = createSignal(0)

  let label = gtk_label_new($count[])

  createEffect do ():
    label.gtk_label_set_text(cstring $count[])

  proc incHello() =
    count[] = count[] + 1

  gui:
    Button(label=count[])

  var data = ClosureProc(prc: cast[ClosureProc.prc](incHello.rawProc()), env: incHello.rawEnv())
  GC_Ref(data)
  let callback = callClosure[tuple[]]
  discard g_signal_connect(button, "clicked", callback, cast[pointer](data));

  gtk_box_append(box, label)

# discard g_signal_connect(app, "activate", activate, nil);
# discard g_application_run(app)
# g_object_unref(pointer(app))
