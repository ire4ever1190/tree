import asyncdispatch
import unittest
import webdriver/[firefox, driver]

var testSuiteName* = ""
  ## So we can make our tests run in a suite even though they don't know it

proc selectorText*(d: Driver, selector: string): Future[string] {.async.} =
  ## Returns the text that corresponds to a CSS selector
  return d.getElementText(d.getElementBySelector(selector).await()).await()

# TODO: Why stack traces for async are pointing to asyncmacro. Might need to place line pragma in asyncmacro.nim:170
proc selectorClick*(d: Driver, selector: string) {.async.} =
  ## Clicks the element that matches a selector
  await d.elementClick(await d.getElementBySelector(selector))

proc countElements*(d: Driver, selector: string): Future[int] {.async.} =
  ## Counts the number of elements that match a selector
  return d.getElementsByCssSelector(selector).await().len

proc elementExists*(d: Driver, selector: string): Future[bool] {.async.} =
  ## Returns true if the selector can find an item
  return d.countElements(selector).await() > 0

proc updateSuiteName*(name: string) =
  ## Update [testSuiteName] without exposing it
  testSuiteName = name

export unittest, asyncdispatch, firefox, driver
