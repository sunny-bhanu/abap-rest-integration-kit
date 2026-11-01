"! <p class="shorttext synchronized">REST integration kit: consolidated S/F response</p>
"! Collects one result per inbound record. All validation messages of a
"! record are returned together (not just the first), and the overall status
"! is S only when every record succeeded.
CLASS zcl_rik_response_builder DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF c_status,
        success TYPE c LENGTH 1 VALUE 'S',
        failure TYPE c LENGTH 1 VALUE 'F',
      END OF c_status.

    TYPES:
      ty_status TYPE c LENGTH 1,
      BEGIN OF ty_message,
        field TYPE string,
        text  TYPE string,
      END OF ty_message,
      ty_messages TYPE STANDARD TABLE OF ty_message WITH EMPTY KEY,
      BEGIN OF ty_record,
        reference TYPE string,
        status    TYPE ty_status,
        sap_key   TYPE string,
        messages  TYPE ty_messages,
      END OF ty_record,
      ty_records TYPE STANDARD TABLE OF ty_record WITH EMPTY KEY,
      BEGIN OF ty_response,
        status    TYPE ty_status,
        message   TYPE string,
        total     TYPE i,
        succeeded TYPE i,
        failed    TYPE i,
        records   TYPE ty_records,
      END OF ty_response.

    METHODS add_success
      IMPORTING reference   TYPE string
                sap_key     TYPE string OPTIONAL
                message     TYPE string OPTIONAL
      RETURNING VALUE(self) TYPE REF TO zcl_rik_response_builder.

    METHODS add_error
      IMPORTING reference   TYPE string
                field       TYPE string OPTIONAL
                text        TYPE string
      RETURNING VALUE(self) TYPE REF TO zcl_rik_response_builder.

    METHODS has_errors
      RETURNING VALUE(result) TYPE abap_bool.

    METHODS build
      RETURNING VALUE(result) TYPE ty_response.

    METHODS to_json
      RETURNING VALUE(result) TYPE string.

    "! 200 when everything succeeded, 422 when at least one record failed validation
    METHODS http_status
      RETURNING VALUE(result) TYPE i.

  PRIVATE SECTION.
    DATA records TYPE ty_records.
ENDCLASS.



CLASS zcl_rik_response_builder IMPLEMENTATION.

  METHOD add_success.
    self = me.
    IF line_exists( records[ reference = reference ] ).
      RETURN. " a record that already failed stays failed
    ENDIF.
    APPEND VALUE #( reference = reference
                    status    = c_status-success
                    sap_key   = sap_key
                    messages  = COND #( WHEN message IS NOT INITIAL
                                        THEN VALUE #( ( text = message ) ) ) ) TO records.
  ENDMETHOD.


  METHOD add_error.
    self = me.
    ASSIGN records[ reference = reference ] TO FIELD-SYMBOL(<record>).
    IF sy-subrc <> 0.
      APPEND VALUE #( reference = reference ) TO records ASSIGNING <record>.
    ENDIF.
    <record>-status = c_status-failure.
    CLEAR <record>-sap_key.
    APPEND VALUE #( field = field text = text ) TO <record>-messages.
  ENDMETHOD.


  METHOD has_errors.
    result = xsdbool( line_exists( records[ status = c_status-failure ] ) ).
  ENDMETHOD.


  METHOD build.
    result-records   = records.
    result-total     = lines( records ).
    result-failed    = REDUCE i( INIT n = 0 FOR r IN records WHERE ( status = c_status-failure ) NEXT n = n + 1 ).
    result-succeeded = result-total - result-failed.

    IF result-total = 0.
      result-status  = c_status-failure.
      result-message = `No records received`.
    ELSEIF result-failed = 0.
      result-status  = c_status-success.
      result-message = |{ result-total } record(s) processed successfully|.
    ELSE.
      result-status  = c_status-failure.
      result-message = |{ result-failed } of { result-total } record(s) failed|.
    ENDIF.
  ENDMETHOD.


  METHOD to_json.
    result = zcl_rik_json=>to_json( build( ) ).
  ENDMETHOD.


  METHOD http_status.
    result = COND #( WHEN build( )-status = c_status-success THEN 200 ELSE 422 ).
  ENDMETHOD.

ENDCLASS.
