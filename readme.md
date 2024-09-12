# 🌲 Tree

[![Tests](https://github.com/ire4ever1190/tree/actions/workflows/main.yml/badge.svg)](https://github.com/ire4ever1190/tree/actions/workflows/main.yml)

Frontend framework based on signals. It's in the early stages, but it is usable. Don't expect a stable API at the moment.

## Overview

A "Hello World" program looks like this

```nim
import tree

proc App(): Element =
  gui:
    text "Hello World!"

App.renderTo("root")
```

Which can then be compiled with the JS backend and put into a HTML document that has an element with id "root"
