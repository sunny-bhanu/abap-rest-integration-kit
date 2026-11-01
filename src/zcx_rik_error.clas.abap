"! <p class="shorttext synchronized">REST integration kit: error</p>
"! Carries the HTTP status, the response body and whether the failure is
"! transient (worth retrying) so callers can decide without parsing texts.
CLASS zcx_rik_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    DATA text          TYPE string    READ-ONLY.
    DATA http_status   TYPE i         READ-ONLY.
    DATA transient     TYPE abap_bool READ-ONLY.
    DATA response_body TYPE string    READ-ONLY.

    METHODS constructor
      IMPORTING text          TYPE string    OPTIONAL
                http_status   TYPE i         OPTIONAL
                transient     TYPE abap_bool DEFAULT abap_false
                response_body TYPE string    OPTIONAL
                previous      LIKE previous  OPTIONAL.

    METHODS if_message~get_text REDEFINITION.
ENDCLASS.



CLASS zcx_rik_error IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    me->text          = text.
    me->http_status   = http_status.
    me->transient     = transient.
    me->response_body = response_body.
  ENDMETHOD.


  METHOD if_message~get_text.
    result = COND #( WHEN text IS NOT INITIAL THEN text ELSE super->if_message~get_text( ) ).
  ENDMETHOD.

ENDCLASS.
