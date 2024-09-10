import asyncdispatch
import unittest
import webdriver/[firefox, driver]

var testSuiteName* = ""
  ## So we can make our tests run in a suite even though they don't know it

proc selectorText*(d: Driver, selector: string): Future[string] {.async.} =
  ## Returns the text that corresponds to a CSS selector
  return d.getElementText(d.getElementBySelector(selector).await()).await()

proc selectorClick*(d: Driver, selector: string) {.async.} =
  ## Clicks the element that matches a selector
  await d.elementClick(await d.getElementBySelector(selector))

proc elementExists*(d: Driver, selector: string): Future[bool] {.async.} =
  ## Returns true if the selector can find an item
  return d.getElementsByCssSelector(selector).await().len > 0

proc updateSuiteName*(name: string) =
  ## Update [testSuiteName] without exposing it
  testSuiteName = name

export unittest, asyncdispatch, firefox, driver
