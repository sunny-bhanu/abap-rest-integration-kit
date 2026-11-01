"! <p class="shorttext synchronized">REST integration kit: HTTP transport (ABAP Cloud)</p>
"! Uses the released web HTTP client (cl_web_http_client_manager), available
"! in BTP ABAP Environment and S/4HANA 2021 or later. For productive use prefer
"! a destination / communication arrangement over a raw URL, see README.
CLASS zcl_rik_http_transport DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rik_http_transport.

  PRIVATE SECTION.
    METHODS to_method
      IMPORTING method        TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zcx_rik_error.
ENDCLASS.



CLASS zcl_rik_http_transport IMPLEMENTATION.

  METHOD zif_rik_http_transport~send.
    DATA client TYPE REF TO if_web_http_client.

    TRY.
        DATA(destination) = cl_http_destination_provider=>create_by_url( i_url = request-url ).
        client = cl_web_http_client_manager=>create_by_http_destination( destination ).
      CATCH cx_http_dest_provider_error cx_web_http_client_error INTO DATA(setup_error).
        RAISE EXCEPTION NEW zcx_rik_error( text     = setup_error->get_text( )
                                           previous = setup_error ).
    ENDTRY.

    TRY.
        DATA(http_request) = client->get_http_request( ).
        LOOP AT request-headers INTO DATA(header).
          http_request->set_header_field( i_name = header-name i_value = header-value ).
        ENDLOOP.
        IF request-body IS NOT INITIAL.
          http_request->set_text( request-body ).
        ENDIF.

        DATA(http_response) = client->execute( to_method( request-method ) ).
        DATA(status) = http_response->get_status( ).

        response = VALUE #( status_code = status-code
                            reason      = status-reason
                            body        = http_response->get_text( ) ).
        LOOP AT http_response->get_header_fields( ) INTO DATA(field).
          APPEND VALUE #( name = field-name value = field-value ) TO response-headers.
        ENDLOOP.

      CATCH cx_web_http_client_error cx_web_message_error INTO DATA(send_error).
        TRY.
            client->close( ).
          CATCH cx_web_http_client_error ##NO_HANDLER.
        ENDTRY.
        RAISE EXCEPTION NEW zcx_rik_error( text      = send_error->get_text( )
                                           transient = abap_true
                                           previous  = send_error ).
    ENDTRY.

    TRY.
        client->close( ).
      CATCH cx_web_http_client_error ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.


  METHOD to_method.
    result = SWITCH #( to_upper( method )
                       WHEN `GET`    THEN if_web_http_client=>get
                       WHEN `POST`   THEN if_web_http_client=>post
                       WHEN `PUT`    THEN if_web_http_client=>put
                       WHEN `PATCH`  THEN if_web_http_client=>patch
                       WHEN `DELETE` THEN if_web_http_client=>delete
                       ELSE THROW zcx_rik_error( text = |HTTP method { method } is not supported| ) ).
  ENDMETHOD.

ENDCLASS.
