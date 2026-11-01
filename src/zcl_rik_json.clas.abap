"! <p class="shorttext synchronized">REST integration kit: JSON helpers</p>
"! Thin wrapper around /ui2/cl_json so that the naming convention of the
"! partner system (camelCase for most REST APIs) is decided in one place.
CLASS zcl_rik_json DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS to_json
      IMPORTING data          TYPE any
                pretty_name   TYPE /ui2/cl_json=>pretty_name_mode DEFAULT /ui2/cl_json=>pretty_mode-camel_case
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS from_json
      IMPORTING json        TYPE string
                pretty_name TYPE /ui2/cl_json=>pretty_name_mode DEFAULT /ui2/cl_json=>pretty_mode-camel_case
      CHANGING  data        TYPE any
      RAISING   zcx_rik_error.
ENDCLASS.



CLASS zcl_rik_json IMPLEMENTATION.

  METHOD to_json.
    result = /ui2/cl_json=>serialize( data        = data
                                      pretty_name = pretty_name
                                      compress    = abap_true ).
  ENDMETHOD.


  METHOD from_json.
    IF json IS INITIAL.
      RAISE EXCEPTION NEW zcx_rik_error( text = `Request body is empty` http_status = 400 ).
    ENDIF.

    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json        = json
                                             pretty_name = pretty_name
                                   CHANGING  data        = data ).
      CATCH cx_sy_conversion_error cx_sy_move_cast_error INTO DATA(error).
        RAISE EXCEPTION NEW zcx_rik_error( text        = |Invalid JSON: { error->get_text( ) }|
                                           http_status = 400
                                           previous    = error ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
