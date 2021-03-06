#lang racket

;; Helper functions used in macros.

(require (except-in ffi/unsafe ->)
         rackunit
         racket/contract
         syntax/parse
         (only-in accelerack/private/types acc-element-type? acc-scalar? acc-int? acc-element?
                  acc-type?)
         )

(provide
  (contract-out
   [validate-literal (-> acc-element-type?
                         (listof exact-nonnegative-integer?)
                         any/c (or/c #t string?))]
   [infer-element-type (-> syntax? syntax?)]
   [infer-array-type   (-> syntax? syntax?)]
   ))

;; Returns #t if everything checks out.  Otherwise returns an
;; explanation of the problem in a string.
(define (validate-literal typ shp dat)
  (define (mkpred ty)
    (match ty
      ['Bool boolean?]
      ['Int  acc-int?]
      ['Double flonum?]
      [`#( ,tys ...)
       (let ((preds (map mkpred tys)))
         (if (andmap procedure? preds)             
             (lambda (x)
               (if (vector? x)
                   (format "Expected tuple of type ~a, found: ~a\n" ty x)
                   (squish (map (lambda (f y) (f y))
                                preds (vector->list x)))))
             (squish (filter string? preds))))]
      [else (format "Unexpected type for array element: ~a\n" ty)]))

  ;; This is tedious because it tries to avoid throwing an exception:
  (define (lenmatch l s)
    (cond
      [(acc-element? l)
       (if (null? s) #t
           (format "Wrong nesting depth.  Expected something of shape ~a, found ~a.\n" s l))]
      [(null? l) #t] ;; zero-length dim is always ok.      
      [(list? l)
       (if (= (length l) (car s))
           (squish (map (lambda (x) (lenmatch x (cdr s))) l))
           (format "Literal array data of wrong length.  Expected ~a things, found ~a, in:\n ~a\n"
                   (car s) (length l) l))]
      [else (format "Unexpected expression where array data was expected: ~a\n"
                    l)]))

  ;; Apply to each element, disregarding nesting level.
  (define (deep-map f dat)
    (cond
      [(pair? dat) (map (lambda (x) (deep-map f x)) dat)]
      [else (f dat)]))
  ;; Take a mix of #t's and strings in an arbitrary sexp.  Append the
  ;; strings separated by newlines.  If no strings found, return #t.
  (define (squish x)
    (cond
      [(eq? #t x) #t]
      [(string? x) x]
      [(null? x) #t]
      [(pair? x)
       (let ((fst (squish (car x)))
             (snd (squish (cdr x))))
         (if (eq? fst #t) snd
             (if (eq? snd #t) fst
                 (string-append fst snd))))]
      [else (error 'validate-literal "internal error.  Squish function got: ~a\n" x)]))
  
  (let ((len-check (lenmatch dat shp))
        (pred (mkpred typ)))
    (if (not (procedure? pred))
        pred
        (if (eq? len-check #t)
            (squish (deep-map (lambda (el)
                                (if (pred el) #t
                                    (format "Array element ~a does not match expected type ~a\n"
                                            el typ)))
                              dat))
            len-check))))


; Syntax -> Syntax (acc-element-type?)

;; This works on anything that satisfies acc-element?
;; Plus, this also currently accepts array literal data, as produced
;; by acc-array->sexp or used inside the (acc-array ...) form.  In
;; this case it still returns only the *element* type.
(define (infer-element-type d)
  (syntax-parse d
    [_:boolean #'Bool ]
    [_:number (if (flonum? (syntax-e d)) #'Double #'Int)]
    [#(v ...) #`(#,@(list->vector (map infer-element-type (syntax->list #'(v ...)))))]
    ;; To get the element type we dig inside any arrays:
    [(v more ...) (infer-element-type #'v)]
    ))

;; This interprets the argument as an array, even if it is zero dimensional.
(define (infer-array-type d)
  (define (count d)
    (syntax-parse d
      [(v more ...) (add1 (count #'v))]
      [else 0]))
  #`(Array #,(count d) #,(infer-element-type d)))


(module+ test
  
  (test-equal? "infer-array-type1"
               (syntax->datum (infer-array-type #'((3))))
               '(Array 2 Int))
  
  (test-equal? "infer-array-type2"
               (syntax->datum (infer-array-type #'( #(3 4.4))))
               '(Array 1 #(Int Double))))
