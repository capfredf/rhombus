#lang rhombus/scribble/manual
@(import:
    "common.rhm" open)

@title{Ports}

A @deftech{port} is an input or output stream for a file, network
connection, terminal, etc. An @tech{input port} is specifically for
input, while an @tech{output port} is specifically for
output; it is possible for an object to be both an input and output port.

@doc(
  annot.macro 'Port'
  annot.macro 'Port.EOF'
){

 The @rhombus(Port, ~annot) annotation is satisfied by a @tech{port}.
 See also @rhombus(Port.Input, ~annot) and @rhombus(Port.Output, ~annot).

 The @rhombus(Port.EOF, ~annot) annotation is satisfied by the
 @rhombus(Port.eof) value.

}

@doc(
 def Port.eof :: Port.EOF
 bind.macro 'Port.eof'
){

 The @rhombus(Port.eof) value represents an end-of-file (distinct from
 all other values), and the @rhombus(Port.eof) binding match matches that
 value.

}

@doc(
 enum Port.Mode:
   binary
   text
){

 Modes for reading and writing files that determine how newlines are
 read and written.

}
