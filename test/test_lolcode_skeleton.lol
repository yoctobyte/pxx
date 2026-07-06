BTW LOLCODE frontend skeleton test (feature-esoteric-lolcode probe)
HAI 1.2
  I HAS A x ITZ 10
  I HAS A y ITZ SUM OF x AN 32
  I HAS A msg ITZ "HAI WORLD"
  VISIBLE msg
  VISIBLE "y is " AN y
  BOTH SAEM y AN 42, O RLY?
    YA RLY
      VISIBLE "saem correct"
    NO WAI
      VISIBLE "saem BROKEN"
  OIC
  I HAS A i ITZ 0
  I HAS A acc ITZ 0
  IM IN YR adder
    i R SUM OF i AN 1
    acc R SUM OF acc AN i
    BOTH SAEM i AN 5, O RLY?
      YA RLY
        GTFO
    OIC
  IM OUTTA YR adder
  VISIBLE "acc is " AN acc
  DIFFRINT acc AN 15, O RLY?
    YA RLY
      VISIBLE "diffrint BROKEN"
    NO WAI
      VISIBLE SMOOSH "smoosh" AN " " AN "works" MKAY
  OIC
KTHXBYE
