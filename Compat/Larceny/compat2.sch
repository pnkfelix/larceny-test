; Copyright 1998 Lars T Hansen.
;
; $Id$
;
; Larceny -- second part of compatibility code
; This file ought to be compiled, but doesn't have to be.
;
; 20 August 1999

(define host-system 'larceny)		; Don't remove this!

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; A well-defined sorting procedure.

(define compat:sort (lambda (list less?) (sort list less?)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Well-defined character codes.
; Returns the UCS-2 code for a character.

(define compat:char->integer char->integer)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Input and output

(define (write-lop item port)
  (lowlevel-write item port)
  (newline port)
  (newline port))

(define write-fasl-datum lowlevel-write)

; The power of self-hosting ;-)

(define (misc->bytevector x)
  (let ((bv (bytevector-like-copy x)))
    (typetag-set! bv $tag.bytevector-typetag)
    bv))

(define string->bytevector misc->bytevector)

(define bignum->bytevector misc->bytevector)

(define (flonum->bytevector x)
  (clear-first-word (misc->bytevector x)))

(define (compnum->bytevector x)
  (clear-first-word (misc->bytevector x)))

; Clears garbage word of compnum/flonum; makes regression testing much
; easier.

(define (clear-first-word bv)
  (bytevector-like-set! bv 0 0)
  (bytevector-like-set! bv 1 0)
  (bytevector-like-set! bv 2 0)
  (bytevector-like-set! bv 3 0)
  bv)

(define (list->bytevector l)
  (let ((b (make-bytevector (length l))))
    (do ((i 0 (+ i 1))
	 (l l (cdr l)))
	((null? l) b)
      (bytevector-set! b i (car l)))))

(define bytevector-word-ref 
  (let ((two^8  (expt 2 8))
	(two^16 (expt 2 16))
	(two^24 (expt 2 24)))
    (lambda (bv i)
      (+ (* (bytevector-ref bv i) two^24)
	 (* (bytevector-ref bv (+ i 1)) two^16)
	 (* (bytevector-ref bv (+ i 2)) two^8)
	 (bytevector-ref bv (+ i 3))))))

;(define (twobit-format fmt . rest)
;  (let ((out (open-output-string)))
;    (apply format out fmt rest)
;    (get-output-string out)))

(define twobit-format format)

; This needs to be a random number in both a weaker and stronger sense
; than `random': it doesn't need to be a truly random number, so a sequence
; of calls can return a non-random sequence, but if two processes generate
; two sequences, then those sequences should not be the same.
;
; Gross, huh?

'(define (an-arbitrary-number)
  (system "echo \\\"`date`\\\" > a-random-number")
  (let ((x (string-hash (call-with-input-file "a-random-number" read))))
    (delete-file "a-random-number")
    x))

; More portable but still gross.  No worse race condition than the 
; previous, at least.

(define (an-arbitrary-number)
  (call-with-output-file "a-random-number"
    (lambda (out)
      (display "Hello, sailor!" out)
      (newline out)))
  (let ((s (open-output-string)))
    (display (file-modification-time "a-random-number") s)
    (let ((x (string-hash (get-output-string s))))
      (delete-file "a-random-number")
      x)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Miscellaneous

(define cerror error)

; eof
