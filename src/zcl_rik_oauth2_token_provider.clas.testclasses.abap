CLASS ltd_transport DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rik_http_transport.
    DATA response TYPE zif_rik_http_transport=>ty_response.
    DATA requests TYPE STANDARD TABLE OF zif_rik_http_transport=>ty_request WITH EMPTY KEY.
ENDCLASS.

CLASS ltd_transport IMPLEMENTATION.
  METHOD zif_rik_http_transport~send.
    APPEND request TO requests.
    response = me->response.
  ENDMETHOD.
ENDCLASS.


CLASS ltd_clock DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rik_clock.
    DATA current TYPE utclong.
ENDCLASS.

CLASS ltd_clock IMPLEMENTATION.
  METHOD zif_rik_clock~now.
    result = current.
  ENDMETHOD.

  METHOD zif_rik_clock~wait ##NEEDED.
  ENDMETHOD.
ENDCLASS.


CLASS ltc_token_provider DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA transport TYPE REF TO ltd_transport.
    DATA clock     TYPE REF TO ltd_clock.
    DATA cut       TYPE REF TO zif_rik_token_provider.

    METHODS setup.
    METHODS caches_token             FOR TESTING RAISING cx_static_check.
    METHODS renews_before_expiry     FOR TESTING RAISING cx_static_check.
    METHODS encodes_form_body        FOR TESTING RAISING cx_static_check.
    METHODS raises_on_http_error     FOR TESTING RAISING cx_static_check.
ENDCLASS.


CLASS ltc_token_provider IMPLEMENTATION.

  METHOD setup.
    transport = NEW #( ).
    transport->response = VALUE #( status_code = 200
                                   body = `{"access_token":"abc","token_type":"bearer","expires_in":120}` ).
    clock = NEW #( ).
    clock->current = utclong_current( ).
    cut = NEW zcl_rik_oauth2_token_provider(
            config    = VALUE #( token_url     = `https://login.example.com/oauth2/token`
                                 client_id     = `my-client`
                                 client_secret = `s3cr&t`
                                 expiry_skew_seconds = 60 )
            transport = transport
            clock     = clock ).
  ENDMETHOD.


  METHOD caches_token.
    cl_abap_unit_assert=>assert_equals( exp = `Bearer abc` act = cut->get_authorization( ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Bearer abc` act = cut->get_authorization( ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( transport->requests ) ).
  ENDMETHOD.


  METHOD renews_before_expiry.
    cut->get_authorization( ).

    " expires_in 120 minus 60 seconds skew: still valid after 59 seconds ...
    clock->current = utclong_add( val = clock->current seconds = 59 ).
    cut->get_authorization( ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( transport->requests ) ).

    " ... and renewed after 61
    clock->current = utclong_add( val = clock->current seconds = 2 ).
    cut->get_authorization( ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( transport->requests ) ).
  ENDMETHOD.


  METHOD encodes_form_body.
    cut->get_authorization( ).

    DATA(request) = transport->requests[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = `POST` act = request-method ).
    cl_abap_unit_assert=>assert_char_cp( exp = 'grant_type=client_credentials*' act = request-body ).
    cl_abap_unit_assert=>assert_char_cp( exp = '*client_secret=s3cr%26t*'      act = request-body ).
  ENDMETHOD.


  METHOD raises_on_http_error.
    transport->response = VALUE #( status_code = 401 body = `{"error":"invalid_client"}` ).

    TRY.
        cut->get_authorization( ).
        cl_abap_unit_assert=>fail( `exception expected` ).
      CATCH zcx_rik_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = 401 act = error->http_status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
