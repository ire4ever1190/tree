import std/[strformat, os, osproc, unittest, asyncdispatch, paths]
import std/macros
import pkg/webdriver/firefox

from pages/utils import updateSuiteName

macro testFile(title, srcFile: static[string]): untyped =
  ## Tests a file.
  ## File should contain two blocks of code where the JS code gets enabled when `buildPage` is defined
  ## and the test code that runs when it is not defined.
  ## Test code should be contained inside a proc called `test` that is async and exported.
  ## See `pages/` for examples
  result = newStmtList()
  let
    outputSym = genSym(nskLet, "output")
    exitCodeSym = genSym(nskLet, "exitCode")
    moduleSym = ident"testModule"
    driverSym = ident"driver"

    jsFile = srcFile.Path().changeFileExt("js")
    htmlFile = currentSourcePath.Path.parentDir() / Path"pages/index.html"
    nimFile = currentSourcePath.Path.parentDir() / Path"pages" / Path(srcFile)
  # Add test for compiling
  let compileCode = quote:
    # TODO: Compile using nimble so that the current src version is used
    let (`outputSym`, `exitCodeSym`) = execCmdEx(getCurrentCompilerExe() & " js -d:buildPage " & string(`nimFile`))

  let compileTest = quote:
    test "Compile " & `srcFile`:
      checkpoint `outputSym`
      check `exitCodeSym` == QuitSuccess
  # Import the test module
  let importStmt = nnkImportStmt.newTree(
    nnkInfix.newTree(
      ident"as",
      nnkInfix.newTree(
        ident"/",
        ident"pages",
        ident srcFile
      ),
      moduleSym
    )
  )
  # And create the suite
  result = quote:
    `importStmt`
    suite `title`:
      updateSuiteName(`title`)
      # Always compile the code, but only check the compile if that test is ran
      `compileCode`
      `compileTest`
      # Navigate to the page before the tests
      waitFor `driverSym`.setUrl("file://" & string(`htmlFile`) & "?file=" & string(`jsFile`))
      # Run tests
      waitFor `moduleSym`.tests(`driverSym`)
    updateSuiteName("")
# Start up the browser
let driver = newFirefoxDriver()
waitFor driver.startSession(headless=true)

# Run all the page tests
testFile "Text Elements", "text.nim"

# Clean up
waitFor driver.close()
