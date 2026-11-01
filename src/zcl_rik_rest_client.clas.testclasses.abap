"----------------------------------------------------------------------
" Test doubles
"----------------------------------------------------------------------
CLASS ltd_transport DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rik_http_transport.
    DATA responses TYPE STANDARD TABLE OF zif_rik_http_transport=>ty_response WITH EMPTY KEY.
    DATA requests  TYPE STANDARD TABLE OF zif_rik_http_transport=>ty_request WITH EMPTY KEY.
ENDCLASS.

CLASS ltd_transport IMPLEMENTATION.
  METHOD zif_rik_http_transport~send.
    APPEND request TO requests.
    IF responses IS INITIAL.
      RAISE EXCEPTION NEW zcx_rik_error( text = `connection refused` transient = abap_true ).
    ENDIF.
    response = responses[ 1 ].
    DELETE responses INDEX 1.
  ENDMETHOD.
ENDCLASS.


CLASS ltd_token DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rik_token_provider.
    DATA issued      TYPE i.
    DATA invalidated TYPE i.
  PRIVATE SECTION.
    DATA current TYPE string.
ENDCLASS.

CLASS ltd_token IMPLEMENTATION.
  METHOD zif_rik_token_provider~get_authorization.
    IF current IS INITIAL.
      issued += 1.
      current = |token-{ issued }|.
    ENDIF.
    result = |Bearer { current }|.
  ENDMETHOD.

  METHOD zif_rik_token_provider~invalidate.
    CLEAR current.
    invalidated += 1.
  ENDMETHOD.
ENDCLASS.


CLASS ltd_clock DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rik_clock.
    TYPES ty_waits TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    DATA waits TYPE ty_waits.
ENDCLASS.

CLASS ltd_clock IMPLEMENTATION.
  METHOD zif_rik_clock~now.
    result = utclong_current( ).
  ENDMETHOD.

  METHOD zif_rik_clock~wait.
    APPEND milliseconds TO waits.
  ENDMETHOD.
ENDCLASS.


"----------------------------------------------------------------------
" Tests
"----------------------------------------------------------------------
CLASS ltc_rest_client DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA transport TYPE REF TO ltd_transport.
    DATA token     TYPE REF TO ltd_token.
    DATA clock     TYPE REF TO ltd_clock.
    DATA cut       TYPE REF TO zcl_rik_rest_client.

    METHODS setup.
    METHODS queue
      IMPORTING status  TYPE i
                headers TYPE zif_rik_http_transport=>ty_headers OPTIONAL.
    METHODS header_of
      IMPORTING index         TYPE i
                name          TYPE string
      RETURNING VALUE(result) TYPE string.

    METHODS adds_token_and_accept_header  FOR TESTING RAISING cx_static_check.
    METHODS retries_get_on_503            FOR TESTING RAISING cx_static_check.
    METHODS refreshes_token_once_on_401   FOR TESTING RAISING cx_static_check.
    METHODS post_not_retried_without_key  FOR TESTING RAISING cx_static_check.
    METHODS post_retried_with_key         FOR TESTING RAISING cx_static_check.
    METHODS gives_up_after_max_attempts   FOR TESTING RAISING cx_static_check.
    METHODS honours_capped_retry_after    FOR TESTING RAISING cx_static_check.
ENDCLASS.


CLASS ltc_rest_client IMPLEMENTATION.

  METHOD setup.
    transport = NEW #( ).
    token     = NEW #( ).
    clock     = NEW #( ).
    cut = NEW #( base_url       = `https://api.example.com`
                 transport      = transport
                 token_provider = token
                 clock          = clock
                 retry_policy   = VALUE #( max_attempts = 3 base_delay_ms = 100 max_delay_ms = 1000 ) ).
  ENDMETHOD.


  METHOD queue.
    APPEND VALUE #( status_code = status headers = headers body = `{}` ) TO transport->responses.
  ENDMETHOD.


  METHOD header_of.
    result = VALUE #( transport->requests[ index ]-headers[ name = name ]-value OPTIONAL ).
  ENDMETHOD.


  METHOD adds_token_and_accept_header.
    queue( 200 ).

    cut->execute( method = `get` path = `/v1/items` ).

    cl_abap_unit_assert=>assert_equals( exp = `https://api.example.com/v1/items` act = transport->requests[ 1 ]-url ).
    cl_abap_unit_assert=>assert_equals( exp = `GET`                    act = transport->requests[ 1 ]-method ).
    cl_abap_unit_assert=>assert_equals( exp = `Bearer token-1`         act = header_of( index = 1 name = `Authorization` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `application/json`       act = header_of( index = 1 name = `Accept` ) ).
  ENDMETHOD.


  METHOD retries_get_on_503.
    queue( 503 ).
    queue( 200 ).

    DATA(response) = cut->execute( method = `GET` path = `/v1/items` ).

    cl_abap_unit_assert=>assert_equals( exp = 200 act = response-status_code ).
    cl_abap_unit_assert=>assert_equals( exp = 2   act = lines( transport->requests ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE ltd_clock=>ty_waits( ( 100 ) ) act = clock->waits ).
  ENDMETHOD.


  METHOD refreshes_token_once_on_401.
    queue( 401 ).
    queue( 200 ).

    DATA(response) = cut->execute( method = `GET` path = `/v1/items` ).

    cl_abap_unit_assert=>assert_equals( exp = 200              act = response-status_code ).
    cl_abap_unit_assert=>assert_equals( exp = 1                act = token->invalidated ).
    cl_abap_unit_assert=>assert_equals( exp = `Bearer token-2` act = header_of( index = 2 name = `Authorization` ) ).
    cl_abap_unit_assert=>assert_initial( clock->waits ).
  ENDMETHOD.


  METHOD post_not_retried_without_key.
    queue( 503 ).

    DATA(response) = cut->send_json( method         = `POST`
                                     path           = `/v1/items`
                                     payload        = VALUE zcl_rik_demo_item_processor=>ty_item( reference = `EXT-1` )
                                     raise_on_error = abap_false ).

    cl_abap_unit_assert=>assert_equals( exp = 503 act = response-status_code ).
    cl_abap_unit_assert=>assert_equals( exp = 1   act = lines( transport->requests ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = '*"reference":"EXT-1"*' act = transport->requests[ 1 ]-body ).
  ENDMETHOD.


  METHOD post_retried_with_key.
    queue( 503 ).
    queue( 201 ).

    DATA(response) = cut->execute(
      method  = `POST`
      path    = `/v1/items`
      body    = `{"reference":"EXT-1"}`
      headers = VALUE #( ( name = zcl_rik_rest_client=>c_idempotency_header value = `EXT-1` ) ) ).

    cl_abap_unit_assert=>assert_equals( exp = 201 act = response-status_code ).
    cl_abap_unit_assert=>assert_equals( exp = 2   act = lines( transport->requests ) ).
  ENDMETHOD.


  METHOD gives_up_after_max_attempts.
    queue( 503 ).
    queue( 503 ).
    queue( 503 ).

    TRY.
        cut->execute( method = `GET` path = `/v1/items` ).
        cl_abap_unit_assert=>fail( `exception expected` ).
      CATCH zcx_rik_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = 503 act = error->http_status ).
    ENDTRY.

    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( transport->requests ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE ltd_clock=>ty_waits( ( 100 ) ( 200 ) ) act = clock->waits ).
  ENDMETHOD.


  METHOD honours_capped_retry_after.
    queue( status = 429 headers = VALUE #( ( name = `retry-after` value = `5` ) ) ).
    queue( 200 ).

    cut->execute( method = `GET` path = `/v1/items` ).

    " 5 seconds requested, capped at max_delay_ms = 1000
    cl_abap_unit_assert=>assert_equals( exp = VALUE ltd_clock=>ty_waits( ( 1000 ) ) act = clock->waits ).
  ENDMETHOD.

ENDCLASS.
