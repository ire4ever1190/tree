import std/[macros, strutils, paths, appdirs, os, strformat, macrocache]
import std/compilesettings

type
  ExampleBlock* = object
    part*: string
    file*: string
    args*: string

# This isn't in stable, but I want to make sure the examples still work
when not compiles($Path"Test"):
  proc `$`(x: Path): string = x.string

proc indentLevel(x: string): int =
  while result < x.len and x[result] in Whitespace:
    result += 1


proc rawHTML(html: string): string =
  ## Inserts raw html into the page
  result = ".. raw:: html\n" & html.indent(2)

const
  counter = CacheCounter"ExampleCounter"
  codeBlocks = CacheTable"CodeBlocks"

template initExampleBlock*(p: string, compileArgs: string): ExampleBlock =
  ExampleBlock(part: p, args: compileArgs, file: $Path(instantiationInfo().filename).splitFile().name)

proc readCode(blk: NimNode): string =
  ## Reads the code from NimNode and returns it as is from the code.
  ## This means that all the formatting stays the same
  # TODO: Add option to output the full code
  let info = blk.lineInfoObj
  let lines = readFile(info.filename).splitLines()

  var indent: int
  for i, line in lines:
    let lineNum = i + 1
    # If this is the first line, find the indent
    if lineNum == info.line:
      indent = line.indentLevel()
    if lineNum >= info.line:
      # If the indent level has decreased, then it means we have encountered code
      # that is outside our code block
      if line.indentLevel() == 0 and line.len >= 0 and not line.isEmptyOrWhitespace():
        break
      result &= line.dedent(indent) & '\n'
  result = result.strip()

proc key(e: ExampleBlock): string = e.file & "_" & e.part

macro multiBlock*(part: static[ExampleBlock], body: untyped): untyped =
  ## Allows you to break up code over multiple blocks, which
  ## can then be checked and outputted in a full block
  let key = part.key()
  if key notin codeBlocks:
    codeBlocks[key] = newStmtList()
  # Find find line we are up to
  var lines = 0
  for blk in codeBlocks[key]:
    lines += blk.strVal.countLines()

  let output = body.readCode()
  codeBlocks[key] &= newLit output
  return newCommentStmtNode(fmt"""

```nim number-lines={lines + 1}
{output}
```

""")


proc makeTempFile(fileName: string | Path): Path =
  ## Returns filename for temp file
  counter.inc
  let exampleNum = counter.value
  appdirs.getTempDir() / Path fmt"temp{fileName}_{exampleNum}.nim"

macro checkMultiBlock*(part: static[ExampleBlock]) =
  ## Should be called at the end of the blocks.
  ## This compiles the code and checks it works
  let key = part.key()

  var output = ""
  # Better to just ignore empty blocks than error
  if key notin codeBlocks: return
  for blk in codeBlocks[key]:
    output &= blk.strVal & "\n"

  let temp = part.file.makeTempFile()
  writeFile(temp.string, output)
  # Check the file with the worst error checking
  let checkResult = staticExec(fmt"{getCurrentCompilerExe()} check {part.args} {temp}")
  if "Error:" in checkResult:
    raise (ref Defect)(msg: checkResult)


macro example*(body: untyped): untyped =
  ## Writes out doc comments that include the source code and a bit of HTML of run the example.
  ## This is like runnableExamples, except it runs on the users browser
  # TODO: Should I run the code in an iFrame?
  # Find the portion of code that corresponds to the example
  let
    info = body.lineInfoObj
    fileName = info.filename.splitFile().name
    tempFile = makeTempFile(filename)
    output = body.readCode()
    # Set the output to correctly be placed beside the source file
    jsFile = (querySetting(outDir).Path / Path"examples" / tempFile.splitPath().tail).changeFileExt("js")
    divName = "exampleDiv" & $counter.value
  writeFile(tempFile.string, output & fmt"""
# Extra code to actual render it
discard document.getElementById("{divName}").insert(Example)
""")
  echo staticExec(fmt"{getCurrentCompilerExe()} js -d:elementID=idk -d:release --out:{jsFile} {tempFile}")
  result = newCommentStmtNode(fmt"""
{rawHTML("<details><summary>Nim code</summary>")}
```nim test number-lines
{output}
```

{rawHTML("</details>")}

{rawHTML("<script type=module async src=\"" & $jsFile.splitFile().name & ".js\"></script>")}

{rawHTML("<div id=" & divName & " style=\"all: unset\"></div>")}

  """)

