! Fortran frontend skeleton test (feature-esoteric-fortran probe):
! implicit first-letter typing (I-N integer, else real), DO loops with
! step, IF/ELSE, PRINT *, int->double widening through shared IR.
program probe
  implicit none
  n = 0
  do i = 1, 10
    n = n + i
  end do
  print *, 'sum is', n

  k = 0
  do j = 10, 2, -2
    k = k + j
  end do
  print *, 'downsum is', k

  x = 2.5
  y = x * 4 + 0.5
  print *, 'y is', y

  if (n == 55) then
    print *, 'sum correct'
  else
    print *, 'sum BROKEN'
  end if

  if (y /= 10.5) then
    print *, 'real BROKEN'
  else
    print *, 'real correct'
  end if
end program probe
