; Copyright 1998 Lars T Hansen.
;
; $Id$
;
; Load script for twobit with SPARC assembler, Unix.

; Only place in the system where the absolute path is needed.

(define *root-directory* "")                               ; Unix
(define *sysdep-file* 
  (string-append *root-directory* "Util/sysdep-unix.sch")) ; Unix

; It should not be necessary to modify any of these.

(load *sysdep-file*)

(load (make-filename *root-directory* "Util" "Configurations" "nbuild-param-sparc.sch"))
(define nbuild-parameter
  (make-nbuild-parameter *root-directory* #f #t #t "Larceny" "Larceny"))

(load (make-filename *root-directory* "Compat" "Larceny" "compat.sch"))
(compat:initialize)
(load (make-filename *root-directory* "Util" "nbuild.sch"))

; eof