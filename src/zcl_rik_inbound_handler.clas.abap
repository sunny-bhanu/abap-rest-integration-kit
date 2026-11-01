"! <p class="shorttext synchronized">REST integration kit: inbound HTTP service handler</p>
"! Handler class for an HTTP service (ABAP Cloud: if_http_service_extension).
"! Accepts POST with a JSON body, delegates to a processor and always answers
"! with the consolidated S/F response. On classic on-premise ICF the same
"! flow fits into IF_HTTP_EXTENSION~HANDLE_REQUEST.
CLASS zcl_rik_inbound_handler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_service_extension.

    METHODS constructor
      IMPORTING processor TYPE REF TO zif_rik_inbound_processor OPTIONAL.

  PRIVATE SECTION.
    DATA processor TYPE REF TO zif_rik_inbound_processor.

    METHODS reply
      IMPORTING response TYPE REF TO if_web_http_response
                status   TYPE i
                body     TYPE string.

    METHODS error_body
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zcl_rik_inbound_handler IMPLEMENTATION.

  METHOD constructor.
    me->processor = COND #( WHEN processor IS BOUND THEN processor ELSE NEW zcl_rik_demo_item_processor( ) ).
  ENDMETHOD.


  METHOD if_http_service_extension~handle_request.
    IF to_upper( request->get_method( ) ) <> `POST`.
      reply( response = response status = 405 body = error_body( `Only POST is supported` ) ).
      RETURN.
    ENDIF.

    DATA(builder) = NEW zcl_rik_response_builder( ).
    TRY.
        processor->process( payload = request->get_text( ) builder = builder ).
        reply( response = response status = builder->http_status( ) body = builder->to_json( ) ).
      CATCH zcx_rik_error INTO DATA(error).
        reply( response = response status = 400 body = error_body( error->get_text( ) ) ).
      CATCH cx_web_message_error INTO DATA(message_error).
        reply( response = response status = 400 body = error_body( message_error->get_text( ) ) ).
    ENDTRY.
  ENDMETHOD.


  METHOD reply.
    TRY.
        response->set_status( i_code = status ).
        response->set_header_field( i_name = `Content-Type` i_value = `application/json` ).
        response->set_text( body ).
      CATCH cx_web_message_error ##NO_HANDLER.
        " nothing more can be sent to the caller at this point
    ENDTRY.
  ENDMETHOD.


  METHOD error_body.
    result = zcl_rik_json=>to_json( VALUE zcl_rik_response_builder=>ty_response(
                                      status  = zcl_rik_response_builder=>c_status-failure
                                      message = text ) ).
  ENDMETHOD.

ENDCLASS.
