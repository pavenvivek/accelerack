#lang racket/base
(require ffi/unsafe
         ffi/unsafe/define)

; One time, I had to restart DrRacket in order for it to reload new copies of .so
(printf "Loading .so files...\n")

(define lib-capi (ffi-lib "./libcapi"))
(define-ffi-definer define-capi lib-capi)

(define lib-rts (ffi-lib "../rts/librts"))
(define-ffi-definer define-rts lib-rts)

(printf "Shared objects loaded without error!\n")

(define-rts ark_init (_fun -> _int))
(define-rts ark_exit (_fun -> _int))
(printf "Aquired init function\n")

(ark_init)
(printf "Initialized RTS\n")

(define-capi entrypoint (_fun _int -> _int))
(printf "Aquired entrypoint function\n")

(printf "Now calling entrypoint:\n")
(entrypoint 33)



(printf "Exiting racket safely\n")
