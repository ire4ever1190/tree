import asyncdispatch
import unittest
import webdriver/[firefox, driver]

let testSuiteName* = " "
  ## To make every test run in a suite. TODO: Set to proper name

proc selectorText*(d: Driver, selector: string): Future[string] {.async.} =
  ## Returns the text that corresponds to a CSS selector
  return d.getElementText(d.getElementBySelector(selector).await()).await()

export unittest, asyncdispatch, firefox, driver
