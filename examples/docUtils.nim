import std/[macros, strutils, paths, appdirs, os, strformat, macrocache]

proc indentLevel(x: string): int =
  while result < x.len and x[result] in Whitespace:
    result += 1

proc rawHTML(html: string): string =
  ## Inserts raw html into the page
  result = ".. raw:: html\n" & html.indent(2)

const counter = CacheCounter"ExampleCounter"

macro example*(body: untyped): untyped =
  ## Writes out doc comments that include the source code and a bit of HTML of run the example.
  # TODO: Should I run the code in an iFrame?
  # Find the portion of code that corresponds to the example
  let info = body.lineInfoObj
  let lines = readFile(info.filename).splitLines()
  var output = ""

  let exampleNum = counter.value
  counter.inc

  let
    fileName = info.filename.splitFile().name
    tempFile = appdirs.getTempDir() / Path fmt"temp{fileName}_{exampleNum}.nim"
  var indent: int
  for i, line in lines:
    let lineNum = i + 1
    # If this is the first line, find the indent
    if lineNum == info.line:
      indent = line.indentLevel()
    if lineNum >= info.line:
      # Stop if we encounter code that is not relevant
      if line.indentLevel() == 0 and line.len >= 0 and not line.isEmptyOrWhitespace():
        echo "Breaking cause ", line
        break
      output &= line.dedent(indent) & '\n'
  output = output.strip()
  let
    jsFile = (info.filename.Path.splitPath().head / tempFile.splitPath().tail).changeFileExt("js")
    divName = "exampleDiv" & $exampleNum
  writeFile(tempFile.string, output & fmt"""
# Extra code to actual render it
discard document.getElementById("{divName}").insert(Example)
""")
  echo staticExec(fmt"{getCurrentCompilerExe()} js -d:elementID=idk -d:release --out:{jsFile} {tempFile}")
  # TODO: Fix line-numbers option in the CSS
  result = newCommentStmtNode(fmt"""
{rawHTML("<details><summary>Nim code</summary>")}
```nim test
{output}
```

{rawHTML("</details>")}

{rawHTML("<script type=module defer src=\"" & $jsFile.splitFile().name & ".js\"></script>")}

{rawHTML("<div id=" & divName & " style=\"border: 1px solid var(--border);background-color: var(--secondary-background);padding: 1em;\"></div>")}

  """)

