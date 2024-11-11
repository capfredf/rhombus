#lang racket/base
(require (for-syntax racket/base
                     syntax/parse/pre
                     shrubbery/print)
         "provide.rkt"
         (submod "annotation.rkt" for-class)
         "call-result-key.rkt"
         "function-arity-key.rkt"
         (submod "bytes.rkt" static-infos)
         (submod "string.rkt" static-infos)
         "static-info.rkt"
         "define-arity.rkt"
         (submod "function.rkt" for-info)
         "class-primitive.rkt"
         "realm.rkt"
         "enum.rkt"
         "binding.rkt"
         "literal.rkt"
         (submod "print.rkt" for-port)
         "rename-parameter.rkt"
         "rhombus-primitive.rkt")

(provide (for-spaces (rhombus/annot
                      rhombus/namespace)
                     Port))

(module+ for-builtin
  (provide input-port-method-table
           output-port-method-table
           output-string-port-method-table))

(define-primitive-class Port port
  #:existing
  #:just-annot
  #:fields ()
  #:namespace-fields
  ([Input Port.Input]
   [Output Port.Output]
   EOF
   [eof Port.eof]
   Mode
   ReadLineMode)
  #:properties ()
  #:methods ())

(define-primitive-class Port.Input input-port
  #:lift-declaration
  #:existing
  #:just-annot
  #:fields ()
  #:namespace-fields
  ([String Port.Input.String]
   [current Port.Input.current]
   [open_bytes Port.Input.open_bytes]
   [open_file Port.Input.open_file]
   [open_string Port.Input.open_string])
  #:properties ()
  #:methods
  ([close Port.Input.close]
   [peek_byte Port.Input.peek_byte]
   [peek_bytes Port.Input.peek_bytes]
   [peek_char Port.Input.peek_char]
   [peek_string Port.Input.peek_string]
   [read_byte Port.Input.read_byte]
   [read_bytes Port.Input.read_bytes]
   [read_char Port.Input.read_char]
   [read_line Port.Input.read_line]
   [read_bytes_line Port.Input.read_bytes_line]
   [read_string Port.Input.read_string]))

(define-primitive-class Port.Output output-port
  #:lift-declaration
  #:existing
  #:just-annot
  #:fields ()
  #:namespace-fields
  ([String Port.Output.String]
   [current Port.Output.current]
   [current_error Port.Output.current_error]
   [open_bytes Port.Output.open_bytes]
   [open_file Port.Output.open_file]
   [open_string Port.Output.open_string]
   [get_bytes Port.Output.String.get_bytes]    ;; temporary: to be removed
   [get_string Port.Output.String.get_string]  ;; temporary: to be removed
   ExistsMode)
  #:properties ()
  #:methods
  ([close Port.Output.close]
   [flush Port.Output.flush]
   [write_bytes Port.Output.write_bytes]
   [write_string Port.Output.write_string]
   [print Port.Output.print]
   [println Port.Output.println]
   [show Port.Output.show]
   [showln Port.Output.showln]))

(define (input-string-port? v)
  (and (input-port? v)
       (string-port? v)))

(define-annotation-syntax Port.Input.String
  (identifier-annotation input-string-port? #,(get-input-port-static-infos)))

(define (output-string-port? v)
  (and (output-port? v)
       (string-port? v)))

(void (set-primitive-contract! '(and/c output-port? string-port?) "Port.Output.String"))
(define-primitive-class Port.Output.String output-string-port
  #:lift-declaration
  #:existing
  #:just-annot
  #:parent #f output-port
  #:fields ()
  #:namespace-fields
  (#:no-methods)
  #:properties ()
  #:methods
  ([get_bytes Port.Output.String.get_bytes]
   [get_string Port.Output.String.get_string]))

(define Port.Input.current (rename-parameter current-input-port 'Port.Input.current))
(set-primitive-who! 'current-input-port 'Port.Input.current)
(define Port.Output.current (rename-parameter current-output-port 'Port.Output.current))
(set-primitive-who! 'current-output-port 'Port.Output.current)
(define Port.Output.current_error (rename-parameter current-error-port 'Port.Output.current_error))
(set-primitive-who! 'current-error-port 'Port.Output.current_error)

(define-static-info-syntax Port.Input.current
  (#%function-arity 3)
  (#%call-result #,(get-input-port-static-infos))
  . #,(get-function-static-infos))

(define-static-info-syntaxes (Port.Output.current Port.Output.current_error)
  (#%function-arity 3)
  (#%call-result #,(get-output-port-static-infos))
  . #,(get-function-static-infos))

(define-annotation-syntax EOF (identifier-annotation eof-object? ()))

(define Port.eof eof)
(define-binding-syntax Port.eof
  (binding-transformer
   (lambda (stxes)
     (syntax-parse stxes
       [(form-id . tail)
        (values (binding-form #'literal-infoer
                              #`([#,eof #,(shrubbery-syntax->string #'form-id)]))
                #'tail)]))))

(define-simple-symbol-enum Mode
  binary
  text)

(define-simple-symbol-enum ReadLineMode
  linefeed
  return
  [return_linefeed return-linefeed]
  any
  [any_one any-one])

(define-simple-symbol-enum ExistsMode
  error
  replace
  truncate
  [must_truncate must-truncate]
  [truncate_replace truncate/replace]
  update
  [can_update can-update]
  append)

(define (check-input-port who ip)
  (unless (input-port? ip)
    (raise-annotation-failure who ip "Port.Input")))

(define (check-output-port who op)
  (unless (output-port? op)
    (raise-annotation-failure who op "Port.Output")))

(define/arity Port.Input.open_bytes
  #:primitive (open-input-bytes)
  #:static-infos ((#%call-result #,(get-input-port-static-infos)))
  (case-lambda
    [(bstr) (open-input-bytes bstr)]
    [(bstr name) (open-input-bytes bstr name)]))

(define/arity (Port.Input.open_file path
                                    #:mode [mode 'binary])
  #:primitive (open-input-file)
  #:static-infos ((#%call-result #,(get-input-port-static-infos)))
  (open-input-file path #:mode mode))

(define/arity Port.Input.open_string
  #:primitive (open-input-string)
  #:static-infos ((#%call-result #,(get-input-port-static-infos)))
  (case-lambda
    [(str) (open-input-string str)]
    [(str name) (open-input-string str name)]))

(define/arity Port.Output.open_bytes
  #:primitive (open-output-bytes)
  #:static-infos ((#%call-result #,(get-output-string-port-static-infos)))
  (case-lambda
    [() (open-output-bytes)]
    [(name) (open-output-bytes name)]))

(define/arity (Port.Output.open_file path
                                     #:exists [exists-in 'error]
                                     #:mode [mode 'binary]
                                     #:permissions [permissions #o666]
                                     #:replace_permissions [replace-permissions? #f])
  #:primitive (open-output-file)
  #:static-infos ((#%call-result #,(get-output-port-static-infos)))
  (define exists (->ExistsMode exists-in))
  (unless exists
    (raise-annotation-failure who exists-in "Port.Output.ExistsMode"))
  (open-output-file path
                    #:exists exists
                    #:mode mode
                    #:permissions permissions
                    #:replace-permissions? replace-permissions?))

(define/arity Port.Output.open_string
  #:primitive (open-output-string)
  #:static-infos ((#%call-result #,(get-output-string-port-static-infos)))
  (case-lambda
    [() (open-output-string)]
    [(name) (open-output-string name)]))

(define (coerce-read-result v)
  (cond
    [(string? v) (string->immutable-string v)]
    [else v]))

(define/method (Port.Input.close port)
  #:primitive (close-input-port)
  (close-input-port port))

(define/method (Port.Input.peek_byte port #:skip_bytes [skip 0])
  #:primitive (peek-byte)
  (peek-byte port skip))

(define/method (Port.Input.peek_bytes port amt #:skip_bytes [skip 0])
  #:primitive (peek-bytes)
  (peek-bytes amt skip port))

(define/method (Port.Input.peek_char port #:skip_bytes [skip 0])
  #:primitive (peek-char)
  (peek-char port skip))

(define/method (Port.Input.peek_string port amt #:skip_bytes [skip 0])
  #:primitive (peek-bytes)
  (coerce-read-result
   (peek-string amt skip port)))

(define/method (Port.Input.read_byte port)
  #:primitive (read-byte)
  (read-byte port))

(define/method (Port.Input.read_bytes port amt)
  #:primitive (read-bytes)
  (read-bytes amt port))

(define/method (Port.Input.read_char port)
  #:primitive (read-char)
  (read-char port))

(define/method (Port.Input.read_line port
                                     #:mode [mode-in 'any])
  #:primitive (read-line)
  (unless (input-port? port) (raise-annotation-failure who port "Port.Input"))
  (define mode (->ReadLineMode mode-in))
  (unless mode
    (check-input-port who port)
    (raise-annotation-failure who mode-in "Port.Input.ReadLineMode"))
  (coerce-read-result
   (read-line port mode)))

(define/method (Port.Input.read_bytes_line port
                                           #:mode [mode-in 'any])
  #:primitive (read-line)
  (unless (input-port? port) (raise-annotation-failure who port "Port.Input"))
  (define mode (->ReadLineMode mode-in))
  (unless mode
    (check-input-port who port)
    (raise-annotation-failure who mode-in "Port.Input.ReadLineMode"))
  (read-bytes-line port mode))

(define/method (Port.Input.read_string port amt)
  #:primitive (read-string)
  (coerce-read-result (read-string amt port)))

(define/method (Port.Output.close port)
  #:primitive (close-output-port)
  (close-output-port port))

(define/method (Port.Output.String.get_bytes port)
  #:primitive (get-output-bytes)
  #:static-infos ((#%call-result #,(get-bytes-static-infos)))
  (get-output-bytes port))

(define/method (Port.Output.String.get_string port)
  #:primitive (get-output-string)
  #:static-infos ((#%call-result #,(get-string-static-infos)))
  (string->immutable-string (get-output-string port)))

(define/method (Port.Output.flush [p (current-output-port)])
  (check-output-port who p)
  (flush-output p))

(define/method (Port.Output.write_bytes port bstr [start 0] [end (and (bytes? bstr) (bytes-length bstr))])
  #:primitive (write-bytes)
  (unless (output-port? port) (raise-annotation-failure who port "Port.Output"))
  (write-bytes bstr port start end)
  (void))

(define/method (Port.Output.write_string port str [start 0] [end (and (string? str) (string-length str))])
  #:primitive (write-string)
  (unless (output-port? port) (raise-annotation-failure who port "Port.Output"))
  (write-string str port start end)
  (void))

(define/method (Port.Output.print port
                                  #:mode [mode 'text]
                                  #:pretty [pretty? default-pretty]
                                  . vs)
  (do-print* who vs port mode pretty?))

(define/method (Port.Output.println port
                                    #:mode [mode 'text]
                                    #:pretty [pretty? default-pretty]
                                    . vs)
  (do-print* who vs port mode pretty?)
  (newline port))

(define/method (Port.Output.show port
                                 #:pretty [pretty? default-pretty]
                                 . vs)
  (do-print* who vs port 'expr pretty?))

(define/method (Port.Output.showln port
                                   #:pretty [pretty? default-pretty]
                                   . vs)
  (do-print* who vs port 'expr pretty?)
  (newline port))

(void (set-primitive-contract! '(or/c 'binary 'text) "Port.Mode"))
