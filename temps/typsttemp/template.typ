#import "@preview/cetz:0.4.2"
#import "@preview/alchemist:0.1.8"
#import "@preview/codly:1.3.0": *
#import "@preview/codly-languages:0.1.1": *
#show: codly-init.with()

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge
#import "@preview/lilaq:0.5.0" as lq
#import "@preview/quick-maths:0.2.1": shorthands
#show: shorthands.with(

)

#import "@preview/quill:0.7.2": *
#import "@preview/unify:0.7.1": num,qty,numrange,qtyrange
#import "@preview/wrap-it:0.1.1": wrap-content
#import "@preview/showybox:2.0.4": showybox

#set text(
  font: "New Computer Modern",
  size: 12pt,
)
#set page(
  paper: "us-letter",
  margin: 1in,
)

#let meta = (
  author: "Raed Mirza",
  course: "COURSE",
  assignment: "ASSIGNMENT",
  date: datetime(year: 2026, month: 2, day: 10),
)

#meta.author

#meta.course

#meta.date.display("[month repr:long] [day], [year]")
#v(.4em)
#show title: set align(center)
#title[#meta.assignment]
#v(1.5em)

#let nord = (
  bg0: rgb("2E3440"),
  bg1: rgb("3B4252"),
  bg2: rgb("434C5E"),
  bg3: rgb("4C566A"),

  fg0: rgb("D8DEE9"),
  fg1: rgb("E5E9F0"),
  fg2: rgb("ECEFF4"),

  frost0: rgb("8FBCBB"),
  frost1: rgb("88C0D0"),
  frost2: rgb("81A1C1"),
  frost3: rgb("5E81AC"),

  red: rgb("BF616A"),
  orange: rgb("D08770"),
  yellow: rgb("EBCB8B"),
  green: rgb("A3BE8C"),
  purple: rgb("B48EAD"),
)

#let accentList = (
  nord.frost1,
  nord.frost2,
  nord.frost3,
  nord.frost0,
)

#let problemCount = counter("problems")
#let partCount = counter("parts")

#let problem(title: "", ..body) = {
  problemCount.step()
  partCount.update(0)

  context {
    let label = {
      if title == "" {
        [== Problem #(problemCount.display())]
      } else {
        title
      }
    }

    let c = calc.rem(problemCount.get().at(0), accentList.len())
    let color = accentList.at(c)

    showybox(
      breakable: true,
      title-style: (
        boxed-style: (
          anchor: (
            x: left,
            y: horizon
          )
        ),
        radius: (top-left: 30pt, bottom-right: 30pt, rest: 0pt),
        color: nord.bg0,
        weight: "bold",
      ),
      body-style: (
        color: nord.bg0,
      ),
      frame: (
      border-color: color.darken(55%),
      title-color:  color,
      body-color:   nord.fg1,
      footer-color: color.lighten(80%),
      title-inset: (x: .7em, y: .7em),
        body-inset: (x: 1em, y: 1.5em),
        radius: (5pt),
        thickness: 1pt,
        dash: "solid",
      ),
      sep: (
        thickness: 1.3pt,
        dash: "densely-dash-dotted",
        gutter: 0.9em,
      ),
      title: label,
      ..body
    )
    v(1em)
  }
}

#let part(label: "") = {
  partCount.step()
  context {
    let name = if label != "" {
      label
    } else {
      partCount.display("a) ")
    }
    [=== #name ]
  }
}

// #problem(title: "CW Approximation of Eilenberg-Maclane Spaces")[
//   #part()

// ][
//   #part()
// ]
