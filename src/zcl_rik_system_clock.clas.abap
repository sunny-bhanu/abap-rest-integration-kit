"! <p class="shorttext synchronized">REST integration kit: system clock</p>
CLASS zcl_rik_system_clock DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rik_clock.
ENDCLASS.



CLASS zcl_rik_system_clock IMPLEMENTATION.

  METHOD zif_rik_clock~now.
    result = utclong_current( ).
  ENDMETHOD.


  METHOD zif_rik_clock~wait.
    " Note: WAIT UP TO triggers a database commit. Do not retry inside an
    " open RAP save sequence; move such calls to a background job / bgPF.
    CHECK milliseconds > 0.
    DATA seconds TYPE f.
    seconds = milliseconds / 1000.
    WAIT UP TO seconds SECONDS.
  ENDMETHOD.

ENDCLASS.
