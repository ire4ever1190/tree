import asyncdispatch
import unittest
import webdriver/[firefox, driver]

let testSuiteName* = " "
  ## To make every test run in a suite. TODO: Set to proper name
export unittest, asyncdispatch, firefox, driver
