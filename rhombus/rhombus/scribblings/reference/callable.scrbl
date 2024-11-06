#lang rhombus/scribble/manual
@(import:
    "common.rhm" open
    "nonterminal.rhm" open)

@title(~tag: "callable"){Callables}

@doc(
  interface Callable
){

@provided_interface_only()

 An interface that a class can implement (publicly or privately) to make
 instances of the class callable as functions. The interface has one
 abstract method, which must be overridden to implement the behavior of
 function calls:

@itemlist(

 @item{@rhombus(call) --- receives the arguments that are passed to the
  instance that is called as a function, and the method's result is the
  result of the function call.}

)

@examples(
  ~defn:
    class Posn(x, y):
      private implements Callable
      private override method call(dx, dy):
        Posn(x + dx, y + dy)
  ~repl:
    def p = Posn(1, 2)
    p
    p(3, 4)
)

}
