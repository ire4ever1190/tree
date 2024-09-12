import tree/store

import std/[unittest, sugar]

import utils

type
  Person = object
    name: string
    age: int
  Classroom = object
    teacher: Person
    students: seq[Person]

proc makeStore(): Store[ClassRoom] =
  createStore(
    Classroom(
      teacher: Person(name: "Greg", age: 47),
      students: @[
          Person(name: "John", age: 18),
          Person(name: "Jack", age: 20),
          Person(name: "Joe", age: 19)
      ]
    )
  )

suite "Selector":
  test "Basic selector for data store":
    let school = makeStore()
    check school.select(it => it.students)() == school.rawGet().students

  test "Doesn't cause updates if value doesn't change":
    let school = makeStore()
    let jack = school.select() do (it: ClassRoom) -> auto:
      for student in it.students:
        if student.name == "Jack":
          return student

    let updates = countUpdates() do ():
      discard jack()

    school.update(Classroom(students: @[Person(name: "Jack", age: 20)]))
    check updates() == 0
    school.update(Classroom(students: @[Person(name: "Jack", age: 21)]))
    check updates() == 1

suite "Updating":
  test "Can update the whole store":
    let school = makeStore()
    let updates = countUpdates() do ():
      discard school()
    school.update(Classroom(teacher: Person(name: "Jake")))
    check updates() == 1
    check school().teacher.name == "Jake"


  test "Can batch updates":
    let school = makeStore()
    let updates = countUpdates() do ():
      discard school()

    school.update() do (it: var Classroom):
      it.teacher.name = "Jake"
      discard it.students.pop()

    check updates() == 1
    check school().students.len == 2
    check school().teacher.name == "Jake"
