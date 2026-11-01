"! <p class="shorttext synchronized">REST integration kit: clock</p>
"! Injected so that token expiry and retry back-off can be tested
"! without waiting for real time to pass.
INTERFACE zif_rik_clock
  PUBLIC.

  METHODS now
    RETURNING VALUE(result) TYPE utclong.

  METHODS wait
    IMPORTING milliseconds TYPE i.

ENDINTERFACE.
