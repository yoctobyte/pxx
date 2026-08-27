(module
  (import "env" "print" (func $print (param i32)))
  (memory (export "memory") 1)
  (global $sp (mut i32) (i32.const 65536))
  (global $exc_pending (mut i32) (i32.const 0))
  (global $exc_val (mut i32) (i32.const 0))

  (func $Thrower (param $n i32) (result i32)
    (local $label i32)
    (local $fp i32)
    ;; prologue: claim 16 bytes of shadow stack
    (global.set $sp (i32.sub (global.get $sp) (i32.const 16)))
    (local.set $fp (global.get $sp))
    (block $exit
     (loop $dispatch
      (block $Btrap
      (block $B2
       (block $B1
        (block $B0
         (br_table $B0 $B1 $B2 $Btrap (local.get $label))
        )  ;; --- B0 ---
         (i32.store (local.get $fp) (i32.const 0))
         (if (i32.gt_s (local.get $n) (i32.const 2))
           (then (local.set $label (i32.const 1)))
           (else (local.set $label (i32.const 2))))
         (br $dispatch)
       )  ;; --- B1 ---
        (global.set $exc_pending (i32.const 1))
        (global.set $exc_val (i32.add (i32.const 100) (local.get $n)))
        (i32.store (local.get $fp) (i32.const 0))  ;; dummy result
        (br $exit)
      )  ;; --- B2 ---
       (i32.store (local.get $fp) (i32.mul (local.get $n) (i32.const 10)))
       (br $exit)
      )  ;; --- $Btrap: unreachable label value ---
      (unreachable)
     )
    )
    ;; epilogue: the ONE place $sp is restored — normal and
    ;; unwind exits both br here
    (global.set $sp (i32.add (global.get $sp) (i32.const 16)))
    (i32.load (local.get $fp))
  )

  (func $Middle (param $n i32) (result i32)
    (local $label i32)
    (local $fp i32)
    (local $fincont i32)
    ;; prologue: claim 16 bytes of shadow stack
    (global.set $sp (i32.sub (global.get $sp) (i32.const 16)))
    (local.set $fp (global.get $sp))
    (block $exit
     (loop $dispatch
      (block $Btrap
      (block $B3
       (block $B2
        (block $B1
         (block $B0
          (br_table $B0 $B1 $B2 $B3 $Btrap (local.get $label))
         )  ;; --- B0 ---
          (i32.store (local.get $fp) (call $Thrower (local.get $n)))
          (if (global.get $exc_pending)
            (then (local.set $fincont (i32.const 3)))   ;; finally -> unwind
            (else
              (call $print (i32.add (i32.const 1000) (i32.load (local.get $fp))))
              (local.set $fincont (i32.const 2))))      ;; finally -> normal
          (local.set $label (i32.const 1))
          (br $dispatch)
        )  ;; --- B1 ---
         (call $print (i32.add (i32.const 2000) (local.get $n)))
         (local.set $label (local.get $fincont))
         (br $dispatch)
       )  ;; --- B2 ---
        (br $exit)
      )  ;; --- B3 ---
       (br $exit)
      )  ;; --- $Btrap: unreachable label value ---
      (unreachable)
     )
    )
    ;; epilogue: the ONE place $sp is restored — normal and
    ;; unwind exits both br here
    (global.set $sp (i32.add (global.get $sp) (i32.const 16)))
    (i32.load (local.get $fp))
  )

  (func $EarlyExit (param $n i32) (result i32)
    (local $label i32)
    (local $fp i32)
    (local $fincE i32)
    ;; prologue: claim 16 bytes of shadow stack
    (global.set $sp (i32.sub (global.get $sp) (i32.const 16)))
    (local.set $fp (global.get $sp))
    (block $exit
     (loop $dispatch
      (block $Btrap
      (block $B3
       (block $B2
        (block $B1
         (block $B0
          (br_table $B0 $B1 $B2 $B3 $Btrap (local.get $label))
         )  ;; --- B0 ---
          (i32.store (local.get $fp) (i32.const -1))
          (if (i32.eq (local.get $n) (i32.const 1))
            (then
              (i32.store (local.get $fp) (i32.const 42))  ;; Exit(42)
              (local.set $fincE (i32.const 3)))           ;; finally -> return
            (else
              (i32.store (local.get $fp) (i32.const 7))
              (local.set $fincE (i32.const 2))))          ;; finally -> after try
          (local.set $label (i32.const 1))
          (br $dispatch)
        )  ;; --- B1 ---
         (call $print (i32.add (i32.const 8000) (local.get $n)))
         (local.set $label (local.get $fincE))
         (br $dispatch)
       )  ;; --- B2 ---
        (i32.store (local.get $fp) (i32.const 99))
        (br $exit)
      )  ;; --- B3 ---
       (br $exit)
      )  ;; --- $Btrap: unreachable label value ---
      (unreachable)
     )
    )
    ;; epilogue: the ONE place $sp is restored — normal and
    ;; unwind exits both br here
    (global.set $sp (i32.add (global.get $sp) (i32.const 16)))
    (i32.load (local.get $fp))
  )

  (func $main
    (local $label i32)
    (local $fp i32)
    (local $fincA i32)
    (local $fincB i32)
    (local $fincC i32)
    (local $fincE2 i32)
    ;; prologue: claim 16 bytes of shadow stack
    (global.set $sp (i32.sub (global.get $sp) (i32.const 16)))
    (local.set $fp (global.get $sp))
    (block $exit
     (loop $dispatch
      (block $Btrap
      (block $B28
       (block $B27
        (block $B26
         (block $B25
          (block $B24
           (block $B23
            (block $B22
             (block $B21
              (block $B20
               (block $B19
                (block $B18
                 (block $B17
                  (block $B16
                   (block $B15
                    (block $B14
                     (block $B13
                      (block $B12
                       (block $B11
                        (block $B10
                         (block $B9
                          (block $B8
                           (block $B7
                            (block $B6
                             (block $B5
                              (block $B4
                               (block $B3
                                (block $B2
                                 (block $B1
                                  (block $B0
                                   (br_table $B0 $B1 $B2 $B3 $B4 $B5 $B6 $B7 $B8 $B9 $B10 $B11 $B12 $B13 $B14 $B15 $B16 $B17 $B18 $B19 $B20 $B21 $B22 $B23 $B24 $B25 $B26 $B27 $B28 $Btrap (local.get $label))
                                  )  ;; --- B0 ---
                                   (i32.store (i32.add (local.get $fp) (i32.const 8)) (call $Middle (i32.const 1)))
                                   (if (global.get $exc_pending)
                                     (then (local.set $fincA (i32.const 3)))   ;; -> A's handler
                                     (else
                                       (call $print (i32.load (i32.add (local.get $fp) (i32.const 8))))
                                       (local.set $fincA (i32.const 2))))      ;; -> after A
                                   (local.set $label (i32.const 1))
                                   (br $dispatch)
                                 )  ;; --- B1 ---
                                  (call $print (i32.const 3001))
                                  (local.set $label (local.get $fincA))
                                  (br $dispatch)
                                )  ;; --- B2 ---
                                 (local.set $label (i32.const 4))
                                 (br $dispatch)
                               )  ;; --- B3 ---
                                (global.set $exc_pending (i32.const 0))
                                (call $print (i32.const 4001))
                                (local.set $label (i32.const 4))
                                (br $dispatch)
                              )  ;; --- B4 ---
                               (i32.store (i32.add (local.get $fp) (i32.const 8)) (call $Middle (i32.const 5)))
                               (if (global.get $exc_pending)
                                 (then (local.set $fincB (i32.const 7)))
                                 (else
                                   (call $print (i32.load (i32.add (local.get $fp) (i32.const 8))))
                                   (local.set $fincB (i32.const 6))))
                               (local.set $label (i32.const 5))
                               (br $dispatch)
                             )  ;; --- B5 ---
                              (call $print (i32.const 3002))
                              (local.set $label (local.get $fincB))
                              (br $dispatch)
                            )  ;; --- B6 ---
                             (local.set $label (i32.const 8))
                             (br $dispatch)
                           )  ;; --- B7 ---
                            (global.set $exc_pending (i32.const 0))
                            (call $print (i32.const 4002))
                            (local.set $label (i32.const 8))
                            (br $dispatch)
                          )  ;; --- B8 ---
                           (i32.store (local.get $fp) (i32.const 0))
                           (local.set $label (i32.const 9))
                           (br $dispatch)
                         )  ;; --- B9 ---
                          (if (i32.lt_s (i32.load (local.get $fp)) (i32.const 4))
                            (then (local.set $label (i32.const 10)))
                            (else (local.set $label (i32.const 14))))
                          (br $dispatch)
                        )  ;; --- B10 ---
                         (i32.store (local.get $fp) (i32.add (i32.load (local.get $fp)) (i32.const 1)))
                         (call $print (i32.add (i32.const 5000) (i32.load (local.get $fp))))
                         (if (i32.eq (i32.load (local.get $fp)) (i32.const 2))
                           (then
                             (global.set $exc_pending (i32.const 1))
                             (global.set $exc_val (i32.const 777))
                             (local.set $fincC (i32.const 12)))   ;; finally -> unwind
                           (else (local.set $fincC (i32.const 13))))  ;; finally -> loop head
                         (local.set $label (i32.const 11))
                         (br $dispatch)
                       )  ;; --- B11 ---
                        (call $print (i32.add (i32.const 6000) (i32.load (local.get $fp))))
                        (local.set $label (local.get $fincC))
                        (br $dispatch)
                      )  ;; --- B12 ---
                       (local.set $label (i32.const 15))
                       (br $dispatch)
                     )  ;; --- B13 ---
                      (local.set $label (i32.const 9))
                      (br $dispatch)
                    )  ;; --- B14 ---
                     (local.set $label (i32.const 16))
                     (br $dispatch)
                   )  ;; --- B15 ---
                    (global.set $exc_pending (i32.const 0))
                    (call $print (i32.const 4003))
                    (local.set $label (i32.const 16))
                    (br $dispatch)
                  )  ;; --- B16 ---
                   (global.set $exc_pending (i32.const 1))
                   (global.set $exc_val (i32.const 888))
                   (local.set $label (i32.const 17))
                   (br $dispatch)
                 )  ;; --- B17 ---
                  (i32.store (i32.add (local.get $fp) (i32.const 4)) (global.get $exc_val))  ;; save current exception
                  (global.set $exc_pending (i32.const 0))
                  (call $print (i32.const 7001))
                  (global.set $exc_pending (i32.const 1))       ;; re-raise
                  (global.set $exc_val (i32.load (i32.add (local.get $fp) (i32.const 4))))
                  (local.set $label (i32.const 18))
                  (br $dispatch)
                )  ;; --- B18 ---
                 (global.set $exc_pending (i32.const 0))
                 (call $print (i32.const 7002))
                 (local.set $label (i32.const 19))
                 (br $dispatch)
               )  ;; --- B19 ---
                (i32.store (local.get $fp) (i32.const 0))
                (local.set $label (i32.const 20))
                (br $dispatch)
              )  ;; --- B20 ---
               (if (i32.lt_s (i32.load (local.get $fp)) (i32.const 5))
                 (then (local.set $label (i32.const 21)))
                 (else (local.set $label (i32.const 25))))
               (br $dispatch)
             )  ;; --- B21 ---
              (i32.store (local.get $fp) (i32.add (i32.load (local.get $fp)) (i32.const 1)))
              (if (i32.eq (i32.load (local.get $fp)) (i32.const 3))
                (then (local.set $fincE2 (i32.const 24)))   ;; finally -> break
                (else (local.set $fincE2 (i32.const 23))))  ;; finally -> loop head
              (local.set $label (i32.const 22))
              (br $dispatch)
            )  ;; --- B22 ---
             (call $print (i32.add (i32.const 8500) (i32.load (local.get $fp))))
             (local.set $label (local.get $fincE2))
             (br $dispatch)
           )  ;; --- B23 ---
            (local.set $label (i32.const 20))
            (br $dispatch)
          )  ;; --- B24 ---
           (local.set $label (i32.const 25))
           (br $dispatch)
         )  ;; --- B25 ---
          (i32.store (i32.add (local.get $fp) (i32.const 8)) (call $EarlyExit (i32.const 1)))
          (if (global.get $exc_pending)
            (then (local.set $label (i32.const 27)))
            (else
              (call $print (i32.load (i32.add (local.get $fp) (i32.const 8))))
              (local.set $label (i32.const 26))))
          (br $dispatch)
        )  ;; --- B26 ---
         (i32.store (i32.add (local.get $fp) (i32.const 8)) (call $EarlyExit (i32.const 0)))
         (if (global.get $exc_pending)
           (then (local.set $label (i32.const 27)))
           (else
             (call $print (i32.load (i32.add (local.get $fp) (i32.const 8))))
             (local.set $label (i32.const 28))))
         (br $dispatch)
       )  ;; --- B27 ---
        (call $print (i32.const -1))
        (unreachable)
      )  ;; --- B28 ---
       (call $print (i32.const 9999))
       (br $exit)
      )  ;; --- $Btrap: unreachable label value ---
      (unreachable)
     )
    )
    ;; epilogue: the ONE place $sp is restored — normal and
    ;; unwind exits both br here
    (global.set $sp (i32.add (global.get $sp) (i32.const 16)))
  )

  (export "main" (func $main))
  (export "sp" (global $sp))
  (export "exc_pending" (global $exc_pending))
)
