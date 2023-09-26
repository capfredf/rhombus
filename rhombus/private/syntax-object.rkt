#lang racket/base
(require (for-syntax racket/base
                     syntax/parse/pre
                     "pack.rkt")
         syntax/parse/pre
         syntax/strip-context
         racket/syntax-srcloc
         racket/symbol
         shrubbery/property
         shrubbery/print
         "provide.rkt"
         "expression.rkt"
         (submod "annotation.rkt" for-class)
         "pack.rkt"
         "realm.rkt"
         "name-root.rkt"
         "tag.rkt"
         "dot-parse.rkt"
         "dotted-sequence.rkt"
         "static-info.rkt"
         "define-arity.rkt"
         (rename-in "srcloc.rkt"
                    [relocate srcloc:relocate])
         "call-result-key.rkt"
         "index-result-key.rkt"
         (submod "dot.rkt" for-dot-provider)
         (submod "srcloc-object.rkt" for-static-info)
         (submod "string.rkt" static-infos)
         (submod "cons-list.rkt" for-compound-repetition))

(provide (for-spaces (rhombus/namespace
                      rhombus/annot)
                     Syntax)
         (for-spaces (rhombus/annot)
                     Term
                     Group
                     Identifier
                     Operator
                     Name
                     IdentifierName))

(module+ for-builtin
  (provide syntax-method-table))

(module+ for-quasiquote
  (provide (for-syntax syntax-static-infos)))

(define-for-syntax syntax-static-infos
  #'((#%dot-provider syntax-instance)))

(define-annotation-syntax Syntax
  (identifier-annotation #'syntax? syntax-static-infos))

(define-annotation-syntax Identifier
  (identifier-annotation #'is-identifier? syntax-static-infos))
(define (is-identifier? s)
  (and (syntax? s)
       (identifier? (unpack-term s #f #f))))

(define-annotation-syntax Operator
  (identifier-annotation #'is-operator? syntax-static-infos))
(define (is-operator? s)
  (and (syntax? s)
       (let ([t (unpack-term s #f #f)])
         (syntax-parse t
           #:datum-literals (op)
           [(op _) #t]
           [_ #f]))))

(define-annotation-syntax Name
  (identifier-annotation #'syntax-name? syntax-static-infos))
(define (syntax-name? s)
  (and (syntax? s)
       (let ([t (unpack-term s #f #f)])
         (or (identifier? t)
             (if t
                 (syntax-parse t
                   #:datum-literals (op)
                   [(op _) #t]
                   [_ #f])
                 (let ([t (unpack-group s #f #f)])
                   (and t
                        (syntax-parse t
                          #:datum-literals (group)
                          [(group _::dotted-operator-or-identifier-sequence) #t]
                          [_ #f]))))))))

(define-annotation-syntax IdentifierName
  (identifier-annotation #'syntax-identifier-name? syntax-static-infos))
(define (syntax-identifier-name? s)
  (and (syntax? s)
       (let ([t (unpack-term s #f #f)])
         (or (identifier? t)
             (and (not t)
                  (let ([t (unpack-group s #f #f)])
                    (and t
                         (syntax-parse t
                           #:datum-literals (group)
                           [(group _::dotted-identifier-sequence) #t]
                           [_ #f]))))))))

(define-annotation-syntax Term
  (identifier-annotation #'syntax-term? syntax-static-infos))
(define (syntax-term? s)
  (and (syntax? s)
       (unpack-term s #f #f)
       #t))

(define-annotation-syntax Group
  (identifier-annotation #'syntax-group? syntax-static-infos))
(define (syntax-group? s)
  (and (syntax? s)
       (unpack-group s #f #f)
       #t))

(define-name-root Syntax
  #:fields
  (literal
   literal_group
   make
   make_op
   make_group
   make_sequence
   make_id
   make_temp_id
   unwrap
   unwrap_op
   unwrap_group
   unwrap_sequence
   unwrap_all
   strip_scopes
   replace_scopes
   relocate
   relocate_span
   to_source_string
   [srcloc Syntax.srcloc]
   [property Syntax.property]
   is_original))

(define-syntax literal
  (expression-transformer
   (lambda (stx)
     (syntax-parse stx
       #:datum-literals (parens quotes group)
       [(_ ((~or parens quotes) (group term)) . tail)
        ;; Note: discarding group properties in this case
        (values #'(quote-syntax term) #'tail)]
       [(_ (~and ((~or parens quotes) . _) gs) . tail)
        (values #`(quote-syntax #,(pack-tagged-multi #'gs)) #'tail)]))))

(define-syntax literal_group
  (expression-transformer
   (lambda (stx)
     (syntax-parse stx
       #:datum-literals (parens quotes group)
       [(_ ((~or parens quotes)) . tail)
        (values #`(quote-syntax #,(pack-multi '())) #'tail)]
       [(_ ((~or parens quotes) g) . tail)
        (values #'(quote-syntax g) #'tail)]))))

;; ----------------------------------------

(define (extract-ctx who ctx-stx
                     #:false-ok? [false-ok? #t]
                     #:update [update #f])
  (and (or (not false-ok?) ctx-stx)
       (let ([t (and (syntax? ctx-stx)
                     (unpack-term ctx-stx #f #f))])
         (unless t
           (raise-argument-error* who rhombus-realm (if false-ok? "maybe(Term)" "Term") ctx-stx))
         (syntax-parse t
           #:datum-literals (op)
           [((~and tag op) id) (if update
                                   (datum->syntax t (list #'tag (update #'id)) t t)
                                   #'id)]
           [(head . tail) (if update
                              (datum->syntax t (cons (update #'head) #'tail) t t)
                              #'head)]
           [_ (if update
                  (update t)
                  t)]))))

(define (starts-alts? ds)
  (and (pair? ds)
       (let ([a (car ds)])
         (define e (if (syntax? a)
                       (let ([t (unpack-term a #f #f)])
                         (and t (syntax-e t)))
                       a))
         (cond
           [(pair? e)
            (define head-stx (car e))
            (define head (if (syntax? head-stx) (syntax-e head-stx) head-stx))
            (case head
              [(alts) #t]
              [else #f])]
           [else #f]))))

(define (do-make who v ctx-stx pre-alts? tail? group?)
  ;; assume that any syntax objects are well-formed, while list structure
  ;; needs to be validated
  (define ctx-stx-t (extract-ctx who ctx-stx))
  (define (invalid)
    (raise-arguments-error* who rhombus-realm
                            (if group?
                                "invalid as a shrubbery group representation"
                                (if tail?
                                    "invalid as a shrubbery term representation"
                                    "invalid as a shrubbery non-tail term representation"))
                            "value" v))
  (define (group-loop l)
    (for/list ([e (in-list l)])
      (group e)))
  (define (group e)
    (cond
      [(and (pair? e)
            (list? e))
       (define head-stx (car e))
       (define head (if (syntax? head-stx) (syntax-e head-stx) head-stx))
       (if (eq? head 'group)
           (cons head-stx
                 (let l-loop ([es (cdr e)])
                   (cond
                     [(null? es) null]
                     [else
                      (define ds (cdr es))
                      (cons (loop (car es)
                                  (starts-alts? ds)
                                  (null? ds))
                            (l-loop ds))])))
           (invalid))]
      [(syntax? e)
       (or (unpack-group e #f #f)
           (invalid))]
      [else (invalid)]))
  (define (loop v pre-alt? tail?)
    (cond
      [(null? v) (invalid)]
      [(list? v)
       (define head-stx (car v))
       (define head (if (syntax? head-stx) (syntax-e head-stx) head-stx))
       (case head
         [(parens brackets braces quotes)
          (cons head-stx (group-loop (cdr v)))]
         [(block)
          (if (or tail? pre-alt?)
              (cons head-stx (group-loop (cdr v)))
              (invalid))]
         [(alts)
          (if tail?
              (cons head-stx
                    (for/list ([e (in-list (cdr v))])
                      (cond
                        [(and (pair? e)
                              (list? e))
                         (define head-stx (car e))
                         (define head (if (syntax? head-stx) (syntax-e head-stx) head-stx))
                         (if (eq? head 'block)
                             (loop e #f #t)
                             (invalid))]
                        [(syntax? e)
                         (define u (unpack-term e #f #f))
                         (define d (and u (syntax-e u)))
                         (or (and d
                                  (eq? 'block (syntax-e (car d)))
                                  u)
                             (invalid))]
                        [else (invalid)])))
              (invalid))]
         [(op)
          (if (and (pair? (cdr v))
                   (null? (cddr v))
                   (let ([op (cadr v)])
                     (or (symbol? op)
                         (identifier? op))))
              v
              (invalid))]
         [else (invalid)])]
      [(pair? v) (invalid)]
      [(syntax? v) (let ([t (unpack-term v #f #f)])
                     (cond
                       [t
                        (define e (syntax-e t))
                        (cond
                          [(pair? e)
                           (define head-stx (car e))
                           (define head (syntax-e head-stx))
                           (case head
                             [(block)
                              (unless (or pre-alt? tail?) (invalid))]
                             [(alts)
                              (unless tail? (invalid))])])
                        t]
                       [else (invalid)]))]
      [else v]))
  (datum->syntax ctx-stx-t (if group? (group v) (loop v pre-alts? tail?))))

(define/arity (make v [ctx-stx #f])
  #:static-infos ((#%call-result #,syntax-static-infos))
  (do-make 'Syntax.make v ctx-stx #t #t #f))

(define/arity (make_op v [ctx-stx #f])
  #:static-infos ((#%call-result #,syntax-static-infos))
  (unless (symbol? v)
    (raise-argument-error* 'Syntax.make_op rhombus-realm "Symbol" v))
  (do-make 'Syntax.make (list 'op v) ctx-stx #t #t #f))

(define/arity (make_group v [ctx-stx #f])
  #:static-infos ((#%call-result #,syntax-static-infos))
  (unless (and (pair? v)
               (list? v))
    (raise-argument-error* 'Syntax.make_group rhombus-realm "NonemptyList" v))
  (define terms (let loop ([es v])
                  (cond
                    [(null? es) null]
                    [else
                     (define ds (cdr es))
                     (cons (do-make 'Syntax.make_group (car es) ctx-stx
                                    (starts-alts? ds)
                                    (null? ds)
                                    #f)
                           (loop ds))])))
  (datum->syntax #f (cons group-tag terms)))

(define/arity (make_sequence v [ctx-stx #f])
  #:static-infos ((#%call-result #,syntax-static-infos))
  (unless (list? v) (raise-argument-error* 'Syntax.make_sequence rhombus-realm "ConsList" v))
  (pack-multi (for/list ([e (in-list v)])
                (do-make 'Syntax.make_sequence e ctx-stx #t #t #t))))

(define/arity (make_id str [ctx #f])
  #:static-infos ((#%call-result #,syntax-static-infos))
  (unless (string? str)
    (raise-argument-error* 'Syntax.make_id rhombus-realm "ReadableString" str))
  (define istr (string->immutable-string str))
  (syntax-raw-property (datum->syntax (extract-ctx 'Syntax.make_id ctx)
                                      (string->symbol istr))
                       istr))

(define/arity (make_temp_id [v #false] #:keep_name [keep-name? #f])
  #:static-infos ((#%call-result #,syntax-static-infos))
  (define id
    (cond
      [keep-name?
       (define sym
         (or (cond
               [(symbol? v) v]
               [(string? v) (string->symbol v)]
               [(syntax? v)
                (define sym (unpack-term v #f #f))
                (and (identifier? sym) (syntax-e sym))]
               [else #f])
             (raise-arguments-error* 'Syntax.make_temp_id rhombus-realm
                                     "name for ~keep_name is not an identifier, symbol, or string"
                                     "name" v)))
       ((make-syntax-introducer) (datum->syntax #f sym))]
      [else
       (car (generate-temporaries (list v)))]))
  (syntax-raw-property id (symbol->immutable-string (syntax-e id))))

(define/arity (unwrap v)
  (cond
    [(not (syntax? v))
     (raise-argument-error* 'Syntax.unwrap rhombus-realm "Syntax" v)]
    [else
     (define unpacked (unpack-term v 'Syntax.unwrap #f))
     (define u (syntax-e unpacked))
     (cond
       [(and (pair? u)
             (eq? (syntax-e (car u)) 'parsed))
        v]
       [else
        (if (and (pair? u)
                 (not (list? u)))
            (syntax->list unpacked)
            u)])]))

(define/arity (unwrap_op v)
  (cond
    [(not (syntax? v))
     (raise-argument-error* 'Syntax.unwrap_up rhombus-realm "Syntax" v)]
    [else
     (syntax-parse (unpack-term v 'Syntax.unwrap #f)
       #:datum-literals (op)
       [(op o) (syntax-e #'o)]
       [else
        (raise-arguments-error* 'Syntax.unwrap_up rhombus-realm
                                "syntax object does not have just an operator"
                                "syntax object" v)])]))

(define-for-syntax list-of-syntax-static-infos
  #`((#%index-result #,syntax-static-infos)
     #,@cons-list-static-infos))

(define/arity (unwrap_group v)
  #:static-infos ((#%call-result #,list-of-syntax-static-infos))
  (cond
    [(not (syntax? v))
     (raise-argument-error* 'Syntax.unwrap_group rhombus-realm "Syntax" v)]
    [else
     (syntax->list (unpack-tail v 'Syntax.unwrap_group #f))]))
  
(define/arity (unwrap_sequence v)
  #:static-infos ((#%call-result #,list-of-syntax-static-infos))
  (cond
    [(not (syntax? v))
     (raise-argument-error* 'Syntax.unwrap_sequence rhombus-realm "Syntax" v)]
    [else
     (syntax->list (unpack-multi-tail v 'Syntax.unwrap_sequence #f))]))

(define/arity (unwrap_all v)
  (define who 'Syntax.unwrap_all)
  (cond
    [(not (syntax? v))
     (raise-argument-error* who rhombus-realm "Syntax" v)]
    [else
     (define (normalize s)
       (cond
         [(not (pair? s)) s]
         [(eq? (car s) 'group)
          (if (null? (cddr s))
              (cadr s)
              s)]
         [(eq? (car s) 'multi)
          (if (and (pair? (cdr s)) (null? (cddr s)))
              (normalize (cadr s))
              s)]
         [else s]))
     (normalize (syntax->datum v))]))

(define/arity (strip_scopes v)
  #:static-infos ((#%call-result #,syntax-static-infos))
  (cond
    [(not (syntax? v))
     (raise-argument-error* 'Syntax.strip_scopes rhombus-realm "Syntax" v)]
    [else
     (strip-context v)]))

(define/arity (replace_scopes v ctx)
  #:static-infos ((#%call-result #,syntax-static-infos))
  (unless (syntax? v)
    (raise-argument-error* 'Syntax.replace_scopes rhombus-realm "Syntax" v))
  (replace-context (extract-ctx 'Syntax.replace_scopes ctx #:false-ok? #f) v))

(define replace_scopes_method
  (lambda (v)
    (let ([replace_scopes (lambda (ctx)
                            (replace_scopes v ctx))])
      replace_scopes)))

(define/arity (relocate stx ctx-stx)
  #:static-infos ((#%call-result #,syntax-static-infos))
  (unless (syntax? stx) (raise-argument-error* 'Syntax.relocate rhombus-realm "Syntax" stx))
  (unless (or (syntax? ctx-stx) (srcloc? ctx-stx) (not ctx-stx))
    (raise-argument-error* 'Syntax.relocate rhombus-realm "Syntax || Srcloc || False" ctx-stx))
  (let ([ctx-stx (and (syntax? ctx-stx)
                      (relevant-source-syntax ctx-stx))])
    (at-relevant-dest-syntax
     stx
     (lambda (stx)
       (if (syntax? ctx-stx)
           (datum->syntax stx (syntax-e stx) ctx-stx ctx-stx)
           (datum->syntax stx (syntax-e stx) ctx-stx stx)))
     (lambda (stx inner-stx)
       stx))))

(define relocate_method
  (lambda (stx)
    (let ([relocate (lambda (ctx-stx)
                      (relocate stx ctx-stx))])
      relocate)))

(define (relevant-source-syntax ctx-stx-in)
  (syntax-parse ctx-stx-in
    #:datum-literals (group block alts parens brackets braces quotes multi op)
    [((~and head (~or group block alts parens brackets braces quotes)) . _) #'head]
    [(multi (g t))
     #:when (syntax-property #'g 'from-pack)
     (relevant-source-syntax #'t)]
    [(multi (g . _)) #'g]
    [(op o) #'o]
    [_ ctx-stx-in]))

;; Extracts from a suitable syntax object inside the source (e.g., a
;; `parens` tag or `group` tag) and similarly applies to a suitable
;; syntax object in the target.
(define (at-relevant-dest-syntax stx proc proc-outer)
  (let loop ([stx stx])
    (syntax-parse stx
      #:datum-literals (group block alts parens brackets braces quotes multi op)
      [((~and head (~or group block alts parens brackets braces quotes)) . rest)
       (define inner (proc #'head))
       (proc-outer (datum->syntax #f (cons inner #'rest)) inner)]
      [((~and m multi) (g t))
       #:when (syntax-property #'g 'from-pack)
       (loop #'t)]
      [((~and m multi) (g . rest))
       (define inner (proc #'g))
       (proc-outer (datum->syntax #f (list #'m (cons inner #'rest))) inner)]
      [((~and tag op) o)
       (define inner (proc #'o))
       (proc-outer (datum->syntax #f (list #'tag inner)) inner)]
      [((~and tag parsed) space o)
       (define inner (proc #'o))
       (datum->syntax #f (list #'tag #'space inner) inner inner)]
      [_
       (proc stx)])))

;; also reraws:
(define/arity (relocate_span stx-in ctx-stxes)
  #:static-infos ((#%call-result #,syntax-static-infos))
  (define stx (and (syntax? stx-in) (unpack-term stx-in #f #f)))
  (unless stx (raise-argument-error* 'Syntax.relocate_span rhombus-realm "Term" stx-in))
  (unless (and (list? ctx-stxes) (andmap syntax? ctx-stxes))
    (raise-argument-error* 'Syntax.relocate_span rhombus-realm "ConsList.of(Syntax)" ctx-stxes))
  
  (at-relevant-dest-syntax
   stx
   (lambda (stx)
     (if (null? ctx-stxes)
         (let* ([stx (syntax-opaque-raw-property (syntax->datum stx (syntax-e stx) #f stx) '())]
                [stx (if (syntax-raw-prefix-property stx)
                         (syntax-raw-prefix-property stx '())
                         stx)]
                [stx (if (syntax-raw-suffix-property stx)
                         (syntax-raw-suffix-property stx '())
                         stx)])
           stx)
         (relocate+reraw (datum->syntax #f ctx-stxes) stx)))
   (lambda (stx inner-stx)
     (let ([stx (syntax-opaque-raw-property (datum->syntax #f (syntax-e stx) inner-stx)
                                            (syntax-opaque-raw-property inner-stx))])
       (let ([pfx (syntax-raw-prefix-property inner-stx)]
             [sfx (syntax-raw-suffix-property inner-stx)])
         (let* ([stx (if pfx
                         (syntax-raw-prefix-property stx pfx)
                         stx)]
                [stx (if sfx
                         (syntax-raw-suffix-property stx sfx)
                         stx)])
           stx))))))

(define relocate_span_method
  (lambda (stx)
    (let ([relocate_span (lambda (ctx-stxes)
                           (relocate_span stx ctx-stxes))])
      relocate_span)))

(define/arity (to_source_string stx)
  #:static-infos ((#%call-result #,string-static-infos))  
  (unless (syntax? stx) (raise-argument-error* 'Syntax.to_source_string rhombus-realm "Syntax" stx))
  (string->immutable-string (shrubbery-syntax->string stx)))

(define/arity (Syntax.srcloc stx)
  #:static-infos ((#%call-result #,srcloc-static-infos))
  (unless (syntax? stx) (raise-argument-error* 'Syntax.srcloc rhombus-realm "Syntax" stx))
  (syntax-srcloc (maybe-respan stx)))

(define/arity Syntax.property
  (case-lambda
    [(stx prop) (syntax-property (extract-ctx 'Syntax.property stx) prop)]
    [(stx prop val) (extract-ctx 'Syntax.property stx
                                 #:update (lambda (t)
                                            (syntax-property t prop val)))]
    [(stx prop val preserved?) (extract-ctx 'Syntax.property stx
                                            #:update (lambda (t)
                                                       (syntax-property t prop val preserved?)))]))

(define property_method
  (lambda (stx)
    (let ([property (case-lambda
                      [(prop) (Syntax.property stx prop)]
                      [(prop val) (Syntax.property stx prop val)]
                      [(prop val preserved?) (Syntax.property stx prop val preserved?)])])
      property)))

(define/arity (is_original v)
  (syntax-original? (extract-ctx 'Syntax.srcloc v #:false-ok? #f)))

(define syntax-method-table
  (hash 'unwrap (method1 unwrap)
        'unwrap_op (method1 unwrap_op)
        'unwrap_group (method1 unwrap_group)
        'unwrap_sequence (method1 unwrap_sequence)
        'unwrap_all (method1 unwrap_all)
        'strip_scopes (method1 strip_scopes)
        'replace_scopes replace_scopes_method
        'relocate relocate_method
        'relocate_span relocate_span_method
        'srcloc (method1 Syntax.srcloc)
        'is_original (method1 is_original)
        'to_source_string (method1 to_source_string)
        'property property_method))

(define-syntax syntax-instance
  (dot-provider
   (dot-parse-dispatch
    (lambda (field-sym field ary 0ary nary fail-k)
      (case field-sym
        [(unwrap) (0ary #'unwrap)]
        [(unwrap_op) (0ary #'unwrap_op)]
        [(unwrap_group) (0ary #'unwrap_group list-of-syntax-static-infos)]
        [(unwrap_sequence) (0ary #'unwrap_sequence list-of-syntax-static-infos)]
        [(unwrap_all) (0ary #'unwrap_all)]
        [(strip_scopes) (0ary #'strip_scopes syntax-static-infos)]
        [(replace_scopes) (nary #'replace_scopes 2 #'replace_scopes syntax-static-infos)]
        [(relocate) (nary #'relocate_method 2 #'relocate syntax-static-infos)]
        [(relocate_span) (nary #'relocate_span_method 2 #'relocate_span syntax-static-infos)]
        [(srcloc) (0ary #'Syntax.srcloc srcloc-static-infos)]
        [(is_original) (0ary #'is_original)]
        [(to_source_string) (0ary #'to_source_string)]
        [(property) (nary #'Syntax.property 14 #'Syntax.property (lambda (n)
                                                                   (if (not (eqv? n 1))
                                                                       syntax-static-infos
                                                                       #'())))]
        [else (fail-k)])))))
