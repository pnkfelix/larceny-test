; -*- Scheme -*-
;
; Scheme 313 runtime system
; Scheme code for bignum arithmetic.
;
; $Id: bignums.scm,v 1.2 91/08/04 20:01:51 lth Exp Locker: lth $
;
; This file has four sections:
;
; The first section contains bignum creators, accessors, and mutators,
; which are machine-dependent in the sense that they `know' the
; endianness of a particular architecture and the layout of a bignum;
; bignums, as seen by these routines, are implemented in terms of bytevectors.
; At some point we probably want the compiler to know about these, but it is
; not vital for performance -- these procedures are called mostly from
; the procedures in section 2.
;
; The second section contains machine-independent procedures which do
; basic operations on parts of bignums, like adding two digits and a
; carry to produce a third digit and a carry. At some level of sophistication,
; the compiler will replace calls to these procedures with an optimized
; sequence of machine instructions at the point of the call.
;
; The third section contains the basic bignum operations as viewed from
; the outside of this module; the procedures defined in this section are
; listed in the `export' list below.
;
; The fourth section contains helper procedures for the procedures in
; section 3.
;
; Logically, a bignum consists of a sign, a digit count, and a number of
; digits. The representation of the sign is abstracted in the variables
; `negative-sign' and `positive-sign'; the signs are fixnum quantities.
; The size (and hence base) of each digit is abstracted in the variable
; `bignum-base'. 
;
; Internally, bignums are created using `bignum-alloc', which allocates
; a bignum of the requested number of digits with a positive sign and a
; value of all-0-digits. The length is extracted using `bignum-length',
; and the sign ditto using `bignum-sign'. The sign can be set using
; `bignum-sign-set!', and the length can be set (and hence bignums can be
; truncated) using `bignum-length-set!'. It is an error to extend a bignum
; beyond its allocated space. Bignum digits are accessed using `bignum-ref'
; and set using `bignum-set!'.
;
; The implementation uses the "classical" algorithms from Knuth, vol II, 2nd
; edition, section 4.3.1. The implementation was also inspired by the 
; techniques discussed in
;  Jon L White: "Reconfigurable, Retargetable Bignums: A Case Study in 
;                Efficient, Portable Lisp System Building",
;  Proceedings of ACM L&FP, 1986


; Here's the list of what procedures which are conceptually exported from
; this module. They do *not* check the types of their arguments!
;
; (export bignum-add 
;         bignum-subtract
;         bignum-multiply
;         bignum-quotient
;         bignum-remainder
;         bignum-divide
;         bignum-negate
;         bignum-=
;         bignum-<=
;         bignum-<
;         bignum->=
;         bignum->
;         bignum-zero?
;         bignum-positive?
;         bignum-negative?
;         bignum->fixnum
;         fixnum->bignum
;         bignum->flonum
;         flonum->bignum)


;-----------------------------------------------------------------------------
; Section 1. All the world's a Sparc.
;
; MACHINE-DEPENDENT STUFF, SOME OF WHICH GOES AWAY WHEN THE COMPILER IS 
; GOOD ENOUGH.
;
; The procedures in Section 1 work on a 32-bit-word, big-endian architecture,
; of which the Sparc is one example. On such an architecture, the layout of
; a bignum is this:
;
;    +------------------------+--------+
;    |   bytevector length    | hdrtag |
;    +----------------+-------+--------+
;    |   sign         |   digitcount   |
;    +----------------+----------------+
;    |   digit 1      |   digit 0      |
;    +----------------+----------------+
;    |   digit 3      |   digit 2      |
;    +----------------+----------------+
;    ...
;
; where the digitcount is the number of 32-bit bignum digits, and the sign
; is 0 for positive and 1 for negative. If the bignum is 0, then the
; sign is immaterial; the `digitcount' field must be 0.
;
; The following code operates on 16-bit digits since these fit conveniently
; in a fixnum; a 32-bit digit is split into 16-bit digits as outlined above.
; This creates a little bit of hairyness in the access pattern; this hair is
; localized in the procedures flagged below as "machine-dependent".
; In particular, the bytevector index of a 16-bit digit with logical index `i'
; is given by the formula
;
;    (+ (* i 2) (if (odd? i) 2 6))
;
; Machine-dependent procedures will later be recognized by the compiler and
; will have their code generated in-line; the machine dependent procedures
; can then go away.

(define byte-base 256)                         ; range of a byte
(define bignum-base (* byte-base byte-base))   ; range of a bignum digit
(define negative-sign 1)                       ; the sign of a negative bignum
(define positive-sign 0)                       ; ditto of a positive one
(define bignum-digits-in-a-fixnum 2)
(define max-bignum-digits (* 65535 2))         ; a lot of digits

; The compiler had better make these into bignums! Debugging versions are
; at the end of the file.
(define smallest-positive-bignum (expt 2 30))
(define largest-negative-bignum (- (+ (expt 2 30) 1)))



; `Bignum-ref' does zero-based referencing of a bignum structure, returning
; a 16-bit digit (adjusted to be a fixnum) from the bignum. 
; This procedure goes away when `big+' etc. are recognized by the compiler.
; Ditto for `bignum-set!'.

(define (bignum-ref a i)
  (let ((base (+ (* i 2) (if (odd? i) 2 6))))
    (+ (* byte-base (bytevector-ref a base))
       (bytevector-ref a (+ base 1)))))

(define (bignum-set! a i v)
  (let ((base (+ (* i 2) (if (odd? i) 2 6))))
    (bytevector-set! a base (quotient v byte-base))
    (bytevector-set! a (+ base 1) (remainder v byte-base))))

; Allocate a bignum given the count of 16-bit digits.

(define (bignum-alloc digits)
  (let ((l (roundup4 (* digits 2))))
    (if (> l max-bignum-digits)
	(error 'generic-arithmetic "Bignum too large.")
	(let ((v (make-bytevector (+ l 4) 0)))
          (bytevector-tag-set! v 'bignum)
	  (bignum-length-set! v (quotient l 2))
	  v))))

; Return the number of 16-bit digits. We check if the high 16-bit digit of
; the high 32-bit digit is 0 (which it may validly be) and return length-1
; if so. The need for this is a result of the way 16-bit digits are mapped
; onto 32-bit digits (or vice versa...).

(define (bignum-length b)
  (let ((l (* 2 (+ (* byte-base (bytevector-ref b 2))
		   (bytevector-ref b 3)))))
    (if (zero? (bignum-ref b (- l 1)))
	(- l 1)
	l)))

; Set the number of 16-bit digits. The number is converted to 32-bit digits,
; which may involve adding a 0 digit at the high end; see comments above.
;
; l is the number of 16-bit digits. To get the number of 32-bit digits,
; we must round up to an even number, then divide by 2. This is equivalent
; to adding 1 and dividing by 2.

(define (bignum-length-set! b l)
  (let ((l (quotient (+ l 1) 2)))
    (bytevector-set! b 2 (quotient l byte-base))
    (bytevector-set! b 3 (remainder l byte-base))))

; Get the sign.

(define (bignum-sign b)
  (bytevector-ref b 1))

; Set the sign.

(define (bignum-sign-set! b s)
  (bytevector-set! b 1 s))

(define (roundup4 n)
  (* (quotient (+ n 3) 4) 4))

; Copy a bignum

(define big-copy bytevector-copy)


;-----------------------------------------------------------------------------
; Section 2.
;
; MACHINE-INDEPENDENT STUFF WHICH GOES AWAY WHEN THE COMPILER IS GOOD ENOUGH
;
; These procedures will later be generated directly by the compiler and this
; (probably abysmally slow, but portable) code will go away.

; Given bignums `a', `b', and `c', a bignum index `i', and a carry digit,
; compute the sum of the ith digits of a and b, with the carry, and put
; that in the ith digit of c, returning the carry.
; The carry is always 1 or 0.

(define (big2+ a b c i carry)
  (let ((r (+ (bignum-ref a i) (bignum-ref b i) carry)))
    (bignum-set! c i (remainder r bignum-base))
    (quotient r bignum-base)))

; Special case: carry propagation.

(define (big1+ a c i carry)
  (let ((r (+ (bignum-ref a i) carry)))
    (bignum-set! c i (remainder r bignum-base))
    (quotient r bignum-base)))

; Given ditto, compute c[i] = a[i] - b[i] - borrow, returning the new borrow.
; The borrow is always 0 or 1.

(define (big2- a b c i borrow)
  (let ((r (- (bignum-ref a i) (bignum-ref b i) borrow)))
    (bignum-set! c i (remainder (+ r bignum-base) bignum-base))
    (if (negative? r) 1 0)))

; Special case: borrow propagation.

(define (big1- a c i borrow)
  (let ((r (- (bignum-ref a i) borrow)))
    (bignum-set! c i (remainder (+ r bignum-base) bignum-base))
    (if (negative? r) 1 0)))

; Given bignums a, b, c, indices i, j, and a carry, compute
;   c[ i+j ] = (a[i]*b[j]+c[i+j]+carry) mod bignum-base
; and return (a[i]*b[j]+c[i+j]+carry) div bignum-base
;
; Since 16bits * 16bits -> 32bits, the straight Scheme implementation of
; this procedure may overflow the fixnum and invoke the bignum routines
; recursively (unless caught by the daisy-chain in the millicode, which will
; happen in the Sparc implementation). This is ugly, but well-defined.
; The machine implementation of this procedure will be able to do
; significantly better.

(define (big2*+ a b c i j carry)
  (let ((r (+ (* (bignum-ref a i) (bignum-ref b j))
	      (bignum-ref c (+ i j))
	      carry)))
    (bignum-set! c (+ i j) (remainder r bignum-base))
    (quotient r bignum-base)))


; The following are used in implementing bignum division. All references
; are to Algorithm D in Knuth vol II, 2nd ed, pp 257-258.

; Step D3: calculate an approximation to q_j, then adjust it if necessary.
; [Needs to be simplified; there's a lot of common subexpressions here.]

(define (big~q u v j)

  (define (toobig? ~q)
    (let ((lv (bignum-length v)))
      (let ((a (* ~q (bignum-ref v (- lv 1))))
	    (b (+ (- (+ (* (bignum-ref u j) bignum-base)
			(bignum-ref u (+ j 1)))
		     (* ~q (bignum-ref v (- lv 1))))
		  (bignum-ref u (+ j 2)))))
	(> a b))))

  (define (approximate)
    (let* ((lv (bignum-length v))
	   (uj (bignum-ref u j))
	   (v1 (bignum-ref v (- lv 1))))
      (if (= uj v1)
	  (- bignum-base 1)
	  (quotient (+ (* uj bignum-base)
		       (bignum-ref u (+ j 1)))
		    v1))))

  (let loop2 ((~q (approximate)))
    (if (big~q-toobig? ~q)
	(loop2 (- ~q 1))
	~q)))


; step D4: multiply and subtract, returning borrow

(define (big*- u v j ~q)
  (let ((newv (multiply-through-by v ~q)))
    (let loop ((i (- j (bignum-length newv))) (k 0) (borrow 0))
      (if (<= i j)
	  (let ((r (- (bignum-ref u i) (bignum-ref newv k) borrow)))
	    (if (negative? r)
		(begin (bignum-set! u i (remainder (+ r bignum-base)
						   bignum-base))
		       (loop (+ i 1) (+ k 1) 1))
		(begin (bignum-set! u i (remainder r bignum-base))
		       (loop (+ i 1) (+ k 1) 0))))
	  borrow))))


; step D6: add back

(define (big-addback u v j)
  (let loop ((i (- j (+ (bignum-length v) 1))) (k 0) (carry 0))
    (cond ((< i j)
	   (let ((r (+ (bignum-ref u i) (bignum-ref v k) carry)))
	     (bignum-set! u (remainder r bignum-base))
	     (loop (+ i 1) (+ k 1) (quotient r bignum-base))))
	  ((= i j)
	   (let ((r (+ (bignum-ref u i) carry)))
	     (bignum-set! u (remainder r bignum-base))))
	  (else
	   '()))))

; Do we need to normalize afterwards here?

(define (big-multiply-through-by b f)
  (let* ((l (bignum-length b))
	 (q (bignum-alloc (+ l 1))))
    (let loop ((i 0) (carry 0))
      (if (< i l)
	  (let ((r (+ (* (bignum-ref b i) f) carry)))
	    (bignum-set! q i (remainder r bignum-base))
	    (loop (+ i 1) (quotient r bignum-base)))
	  (begin (bignum-set! q i carry)
		 q)))))

(define (big-extend-with-zero b)
  '())

;-----------------------------------------------------------------------------
; Section 3.
;
; MACHINE-INDEPENDENT STUFF
;
; Normalization is done in the toplevel routines because that gives us the
; opportunity to fiddle the sign at will, knowing that what we're dealing
; with is a bignum.

; Add two bignums, producing an integer.
;       a + b  ==   a + b
;       a + -b ==   a - b
;      -a + b  == -(a - b)
;      -a + -b == -(a + b)

(define (bignum-add a b)
  (let ((sa (bignum-sign a))
	(sb (bignum-sign b)))
    (let ((c (if (= sa sb)
		 (big-add-digits a b)
		 (big-subtract-digits a b))))
      (if (sign-negative? sa)
	  (flip-sign! c))
      (big-normalize! c))))


; Subtract bignum `b' from bignum `a', producing an integer.
;       a - b  ==   a - b
;       a - -b ==   a + b
;      -a - b  == -(a + b)
;      -a - -b == -(a - b)

(define (bignum-subtract a b)
  (let ((sa (bignum-sign a))
	(sb (bignum-sign b)))
    (let ((c (if (= sa sb)
		 (big-subtract-digits a b)
		 (big-add-digits a b))))
      (if (sign-negative? sa)
	  (flip-sign! c))
      (big-normalize! c))))


; Multiply two bignums, producing an integer.

(define (bignum-multiply a b)
  (let ((sa (bignum-sign a))
	(sb (bignum-sign b)))
    (let ((c (big-multiply-digits a b)))
      (if (not (= sa sb))
	  (bignum-sign-set! c negative-sign))
      (big-normalize! c))))


; Divide bignum `a' by bignum `b', returning the quotient.

(define (bignum-quotient a b)
  (let ((sa (bignum-sign a))
	(sb (bignum-sign b)))
    (let ((c (car (big-divide-digits a b))))
      (if (not (= sa sb))
	  (bignum-sign-set! c negative-sign))
      (big-normalize! c))))


; Divide bignum `a' by bignum `b', returning the remainder.

(define (bignum-remainder a b)
  (let ((sa (bignum-sign a))
	(sb (bignum-sign b)))
    (let ((c (cdr (big-divide-digits a b))))
      (if (not (= sa sb))
	  (bignum-sign-set! c negative-sign))
      (big-normalize! c))))


; Divide bignum `a' by bignum `b', returning an integer if the remainder is 1,
; and a ratnum otherwise.

(define (bignum-divide a b)
  (let ((sa (bignum-sign a))
	(sb (bignum-sign b)))
    (let ((c (big-divide-digits a b)))
      (if (not (= sa sb))
	  (bignum-sign-set! (car c) negative-sign))
      (make-reduced-ratnum (big-normalize! (car c))
			   (big-normalize! (cdr c))))))

; Return the negation of the argument (a new bignum).

(define (bignum-negate a)
  (let ((b (bignum-copy a)))
    (flip-sign! b)
    b))

; relational operators

(define (bignum-= a b)
  (zero? (big-compare a b)))

(define (bignum-<= a b)
  (<= (big-compare a b) 0))

(define (bignum-< a b)
  (< (big-compare a b) 0))

(define (bignum->= a b)
  (>= (big-compare a b) 0))

(define (bignum-> a b)
  (> (big-compare a b) 0))

; unary predicates

(define (bignum-zero? b)
  (zero? (bignum-length b)))

(define (bignum-negative? b)
  (and (sign-negative? (bignum-sign b))
       (not (zero? (bignum-length b)))))

(define (bignum-positive? b)
  (and (sign-positive? (bignum-sign b))
       (not (zero? (bignum-length b)))))

; Coercions

; Assumes the bignum fits in a fixnum.

(define (bignum->fixnum b)
  (let loop ((i (- (bignum-length b) 1)) (n 0))
    (if (negative? i)
	(if (sign-negative? (bignum-sign b))
	    (- n)
	    n)
	(loop (- i 1) (+ (* bignum-base n) (bignum-ref b i))))))

; Can't use `big-normalize!' because it'd convert it back to a fixnum.

(define (fixnum->bignum f)
  (let ((b (bignum-alloc bignum-digits-in-a-fixnum)))
    (let loop ((i 0) (n (abs f)))
      (if (zero? n)
	  (begin (bignum-length-set! b i)
		 (if (negative? f)
		     (bignum-sign-set! b negative-sign))
		 b)
	  (begin (bignum-set! b i (remainder n bignum-base))
		 (loop (+ i 1) (quotient n bignum-base)))))))

(define (bignum->flonum b)
  '())

(define (flonum->bignum f)
  (let ((m (mantissa f))
	(e (- (exponent f) bits-in-mantissa)))
    (if (negative? e)
	(quotient m (expt 2 (abs e)))
	(* m (expt 2 e)))))


;-----------------------------------------------------------------------------
; Section 4.
;
; Helpers.

(define (sign-negative? sign)
  (= sign negative-sign))

(define (sign-positive? sign)
  (= sign positive-sign))

(define (flip-sign! b)
  (if (sign-negative? (bignum-sign b))
      (bignum-sign-set! b positive-sign)
      (bignum-sign-set! b negative-sign)))


; Add the digits of two bignums, producing a third, positive, bignum.

(define (big-add-digits a b)
  (let* ((la   (bignum-length a))
	 (lb   (bignum-length b))
	 (lmax (max la lb))
	 (lmin (min la lb))
	 (c    (bignum-alloc (+ lmax 1))))

      ; add common segments

      (let loop ((i 0) (carry 0))
	(if (< i lmin)
	    (loop (+ i 1) (big2+ a b c i carry))
	    
	    ; add carry thru longest number

	    (let ((rest (if (= i la) b a)))
	      (let loop ((i i) (carry carry))
		(if (< i lmax)
		    (loop (+ i 1) (big1+ rest c i carry))
		    (begin (bignum-set! c i carry)
			   c))))))))


; Subtract the digits of bignum b from the digits of bignum a, producing 
; a third, possibly negative, bignum c.

(define (big-subtract-digits a b)
  (let ((x (big-compare-digits a b)))
    (let ((a (if (negative? x) b a))
	  (b (if (negative? x) a b)))
      (let* ((la   (bignum-length a))
	     (lb   (bignum-length b))
	     (lmax (max la lb))
	     (lmin (min la lb))
	     (c    (bignum-alloc (+ lmax 1)))) ; are you sure?

	(printf "la=%d lb=%d lmax=%d lmin=%d%n" la lb lmax lmin)

	; subtract common segments

	(let loop ((i 0) (borrow 0))
	  (if (< i lmin)
	      (loop (+ i 1) (big2- a b c i borrow))
	  
	      ; subtract borrow through longest number

	      (let ((rest (if (= i la) b a)))
		(let loop ((i i) (borrow borrow))
		  (if (< i lmax)
		      (loop (+ i 1) (big1- rest c i borrow))
		      (begin (if (negative? x)
				 (flip-sign! c))
			     c))))))))))


; Multiply the digits of two positive bignums, producing a third,
; positive, bignum.

(define (big-multiply-digits a b)
  (let* ((la (bignum-length a))
	 (lb (bignum-length b))
	 (lmax (max la lb))
	 (lmin (min la lb))
	 (c    (bignum-alloc (+ la lb))))
    (let loop1 ((ai 0))
      (if (< ai la)
	  (let loop2 ((bi 0) (carry 0))
	    (if (< bi lb)
		(loop2 (+ bi 1) (big2*+ a b c ai bi carry))
		(begin (bignum-set! c (+ ai bi) carry)
		       (loop1 (+ ai 1)))))
	  c))))


; Divide two positive bignums, producing a pair, both elements of which are 
; bignums, the car being the quotient and the cdr being the remainder.
; (btw, we're computing a / b here, not b / a, in case there was a doubt...)
;
; See Knuth vol II, 2nd ed, p 257,258.

(define (big-divide-digits a b)

  ; `a' is a bignum, `b' is a fixnum. Produces a pair of bignums, even if the
  ; remainder is always a fixnum.

  (define (fast-divide a b)
    (let ((q (bignum-alloc (bignum-length a))))
      (let loop ((remainder 0) (i (- (bignum-length a) 1)))
	(if (>= 0 i)
	    (let ((d (+ (* remainder bignum-base) (bignum-ref u i))))
	      (bignum-set! q i (quotient d b))
	      (loop (remainder d b) (- i 1)))))))


  ; `a' and `b' are both bignums, with (length a) >= (length b) and
  ; (length b) > 1. Produces a pair of bignums.

  (define (slow-divide a b)
    (let* ((d  (quotient bignum-base
			 (+ (bignum-ref b (- (bignum-length b) 1)) 1)))
	   (u  (if (= 1 d)
		   (extend-with-0 a)
		   (multiply-through-by a d)))
	   (v  (multiply-through-by b d))
	   (lu (bignum-length u))
	   (lv (bignum-length v))
	   (q  (bignum-alloc (- lu lv))))
      (let loop1 ((j (- lu 1)))
	(if (>= j 0)
	    (let ((~q (big~q u v j)))
	      (let ((borrow (big*- u v j ~q)))
		(bignum-set! q j ~q)
		(if (not (zero? borrow))
		    (begin (bignum-set! q j (- (bignum-ref q j) 1))
			   (big-addback u v j)))
		(loop1 (- j 1))))
	    (cons q (car (fast-divide u d)))))))

  ; maintain some invariants and catch the easy cases.

  (cond ((bignum-zero? b)
	 (error 'generic-arithmetic "Bignum division by zero"))
	((bignum-zero? a)
	 (cons (fixnum->bignum 0) (fixnum->bignum 0)))
	(else
	 (let ((la (bignum-length a))
	       (lb (bignum-length b)))
	   (cond ((> lb la)
		  (let ((r (bignum-copy b)))
		    (bignum-sign-set! b positive-sign)
		    (cons (fixnum->bignum 0) b)))
		 ((= lb 1)
		  (fast-divide a (bignum-ref b 0)))
		 (else
		  (slow-divide a b)))))))


; Compare two bignums, and return 0 if they are equal, a negative number if
; the first is less than the second, and a positive number if the first is
; greater than the second.

(define (big-compare a b)
  (let* ((la (bignum-length a))
	 (lb (bignum-length b))
	 (sa (if (zero? la) positive-sign (bignum-sign a)))
	 (sb (if (zero? lb) positive-sign (bignum-sign b))))
    (cond ((not (= sa sb))
	   (if (sign-negative? sa)
	       -1
	       1))
	  (else
	   (if (sign-negative? sa)
	       (- (big-compare-digits a b))
	       (big-compare-digits a b))))))

(define (big-compare-digits a b)
  (let ((la (bignum-length a))
	(lb (bignum-length b)))
    (if (not (= la lb))
	(- la lb)
	(let loop ((i (- la 1)))
	  (cond ((< i 0)
		 0)
		((= (bignum-ref a i) (bignum-ref b i))
		 (loop (- i 1)))
		(else
		 (- (bignum-ref a i) (bignum-ref b i))))))))

    
; Normalize a bignum -- this involves removing leading zeroes, and, if the
; number is small enough to fit in a fixnum, converting it to a fixum.

(define (big-normalize! b)
  (let loop ((i (- (bignum-length b) 1)))
    (cond ((negative? i)
	   0)
	  ((zero? (bignum-ref b i))
	   (loop (- i 1)))
	  (else
	   (bignum-length-set! b (+ i 1))
	   (if (and (bignum-> b largest-negative-bignum)
		    (bignum-< b smallest-positive-bignum))
	       (bignum->fixnum b)
	       b)))))

(display "; redefining debugging values") (newline)

(define smallest-positive-bignum (integer->bytevector (expt 2 30)))
(define largest-negative-bignum (integer->bytevector (- (+ (expt 2 30) 1))))
