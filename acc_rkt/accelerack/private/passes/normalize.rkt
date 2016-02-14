#lang racket

;; ---------------------------------------------------------------
;; Defines a compiler pass which:
;;  (1) All array operators are directly followed by lambda
;;  (2) Should never throw errors hence can directly operate on sexp
;;      rather than rich syntax expression
;; ---------------------------------------------------------------

(require
 rackunit
 rackunit/text-ui
 racket/match)
(require macro-debugger/expand)


(require racket/trace)
(require (for-syntax racket/trace))
(require accelerack/private/wrappers)
(require
 (for-syntax (except-in racket/base map))
 syntax/parse
 syntax/to-string
 scribble/srcdoc
 racket/trace
 (only-in accelerack/private/global_utils pass-output-chatter)
 accelerack/private/syntax
 (prefix-in r: racket/base))

(require (for-syntax syntax/parse))

(provide (contract-out
          (normalize (-> list? any/c list?)))
         ; test1 test2
         test3 test4 test4b test4c test5 test6)

(define lambda-first-primitive-ls '(map fold zipwith generate stencil3x3))
(define primitive-ls '(vector vector-ref map fold zipwith generate stencil3x3
                       add1 + * - / sqrt))
(define (returns-lambda? exp)
  (match exp
    (`(let ,xls ,y ... ,z) (returns-lambda? z))
    (`(if ,x ,y ,z) (returns-lambda? y))
    (`(lambda (,x ...) ,y ...) #t)
    (`,else #f)))

;; Return set of scalar expressions, add lambda's to environment
(define (normalize-exp-let xls env)
  (if (null? xls)
      (values '() env)
      (let ((x (caar xls))
	    (xp (normalize (cadar xls) env)))
	(let-values (((exp env) (normalize-exp-let (cdr xls) env)))
	  (if (returns-lambda? xp)
	      (values exp (cons `(,x ,xp) env))   ;; Add to env if lambda
	      (values (cons `(,x ,xp) exp) env)))))) ;; Else just let it remain in expression

;; The normalize front end
(define (normalize exp env)
  (let-values (((v sym) (normalize-exp exp env)))
    v))

(define (add-to-env xls e env)
  (if (null? xls)
      env
      (cons `(,(car xls) ,(normalize (car e) env)) (add-to-env (cdr xls) (cdr e) env))))

;; Take a final expression and lambda 
(define (normalize-to-lambda e l x env)
  (match l
    (`(lambda ,x ,y ... ,z) `(,e (lambda ,x ,(normalize z env)) ,@x))
    (`(if ,c ,y ,z) `(if ,c
			 ,(normalize-to-lambda e (normalize y env) x env)
			 ,(normalize-to-lambda e (normalize z env) x env)))
    (`(let ,xls ,a ... ,b)
     `(let ,xls ,@a
           ,(normalize-to-lambda e b x env)))
    ))

;; Environment contains only lambda's for now
;; Anything more ??
(define (normalize-exp exp env)
  (let loop ((exp exp) (env env))
    (match exp
      (`(let ,xls ,b)
       (let*-values (((exp env) (normalize-exp-let xls env)))
	 (let ((bexp (normalize b env)))
	   (if (null? exp)
	       (values bexp env)
	       (values `(let ,exp ,bexp) env)))))
      (`(if ,x ,y ,z) (values `(if ,(normalize x env) ,(normalize y env) ,(normalize z env)) env))
      (`(,e ,l ,x ...) #:when(memq e lambda-first-primitive-ls)
       (let ((l (normalize l env))
             (x (map (lambda(x) (normalize x env)) x)))
         (values (normalize-to-lambda e l x env) env)))

      (`(,p ,x ...) #:when(memq p primitive-ls)
       (let ((x (map (lambda(x) (normalize x env)) x)))
         (values `(,p ,@x) env)))
      ;; Substitute values - When lambda application -- Discarding all values except last since no side effects
      (`((lambda (,x ...) ,y ... ,z) ,e ...) (let ((lenv (add-to-env x e env)))
                                               (values (normalize z lenv) env)))
      ;; (`(lambda ,x ,y ...) (values `(lambda ,x ,@(map (lambda(x) (normalize x env)) y)) env))
      (`(,x ...) (values `,(map (lambda(x) (normalize x env)) x) env))
      (`,x #:when(assq x env) (values (cadr (assq x env)) env))
      ;; RRN: This seems a bit questionable: what about (add1 e)
      (`,x (values x env))
      )))


;; Some test cases
(define (is-normalized? exp)
  (let loop ((exp exp))
    (match exp
      (x #:when (symbol? x) x)
      (n #:when (number? n) n)
      (`(let ([,v ,rhs*] ...) ,b) (and (andmap loop rhs*)
                                     (loop b)))
      (`(if ,x ,y ,z) (and  (loop y) (loop z)))
      ;; Acc-array has literals only, not expressions:
      (`(acc-array ,x) #t)
      (`(,e ,x ,y ...) #:when(memq e lambda-first-primitive-ls)
       (and (loop e) (andmap loop y) (match x
                                       (`(lambda ,xls ,yls) (is-normalized? yls))
                                       (`,els #f))))
      (`(,e ,x ,y ...) #:when (memq e primitive-ls) (and (loop x) (andmap loop y)))
      (`(lambda ,xls ,yls) #f)
      ;; Any other application return false 
      (`(,e ,x ,y) #f)
      (`,x (error 'is-normalized "unexpected expression: ~a\n" x))
      )))

;; Probably invalid
;; (define test1 '(let ((f (lambda(k) (map add1 k))))
;;                  (let ((a (f (acc-array (1 2 3))))
;;                        (b (f (acc-array (1 2 4)))) )
;;                    (map f (generate a b)))))

;; Invalid
;; (define test2 '(let ((f (lambda(k) (map add1 k))))
;;                  (let ((g (lambda(k) (let ((a (f (acc-array (1 2 3))))
;;                                            (b (f (acc-array (1 2 4)))))
;;                                        (map f (generate a b))))))
;;                    (generate f g))))

(define test3 '(let ((f 1))
                 (if (eq? f 1)
                     (acc-array (1 2 3))
                     (acc-array (2 3 4)))))

(define test4 '(let ((f (if #t
			    (lambda(x) x)
			    (lambda(x) (* 2 x)))))
		 (map f (acc-array (1 2 3)))))

(define test4a '(map (lambda(x) (* 2 x)) (acc-array (1 2 3))))

(define test4b '(let ((f (if #t
                             (lambda(x) x)
                             (lambda(x) (* 2 x)))))
                  (let ((a1 (map f (acc-array (1 2 3))))
                        (a2 (acc-array (4 5 6))))
                    a2)
                  ))
(define test4c '(let ((f (if #t
                             (lambda(x) x)
                             (lambda(x) (* 2 x)))))
                  (let ((a1 (map (lambda (x) x) (acc-array (1 2 3))))
                        (a2 (acc-array (4 5 6))))
                    a2)
                  ))

(define test6 '(let ((f (let ((a 1))
			  (lambda(x) (+ a x)))))
		 (map f (acc-array (1 2)))))


(define test5 '(let ((f (let ((x 1))
				(if (eq? x 1)
				    (lambda (x) x)
				    (lambda (x) (* 2 x)))))
		     (g (if (eq? 1 1)
			    (acc-array (1 2 3))
			    (acc-array (2 3 4)))))
		 (map f g)))

(define test7 '(let ((f (let ((x 1))
                          (if (eq? x 1)
                              ((lambda (x) x) (lambda(x) x))
                              (lambda (x) (* 2 x)))))
		     (g (if (eq? 1 1)
			    (acc-array (1 2 3))
			    (acc-array (2 3 4)))))
		 (map f g)))


(define test8
  `(add1 (vector-ref (let ((f (lambda(x) x)))
                       (map f (acc-array (1 2 3)))) 0)))

(define test9 '(let ((a 2)
                     (b (lambda(x y) (* y x))))
                 (let ((l (lambda(x) (b x 2))))
                   (map l (acc-array (1 2 3))))))


;; ********************* TEST CASE ************************
(pretty-print (normalize test9 '()))


;; Passing tests:
(for-each (lambda(x)
            (check-pred is-normalized? x))
     (map (lambda(x) (normalize x '()))
          (list test3 test4 test4a test4b test4c
                test5 test6 test7 test8 test9)))

;; Known failures, FIXME FIXME!
(for-each (lambda (t)
            (check-pred (lambda (x) (not (is-normalized? x)))
                        (normalize t '())))
          (list))
