"! <p class="shorttext synchronized">REST integration kit: inbound processor</p>
INTERFACE zif_rik_inbound_processor
  PUBLIC.

  "! Validates and processes the payload. Every record must end up in the
  "! builder as success or error. Raise zcx_rik_error only for a payload that
  "! cannot be read at all (answered with HTTP 400).
  METHODS process
    IMPORTING payload TYPE string
              builder TYPE REF TO zcl_rik_response_builder
    RAISING   zcx_rik_error.

ENDINTERFACE.
