"! <p class="shorttext synchronized">REST integration kit: REST client with retry</p>
"! Adds the bearer token, refreshes it once on 401 and retries transient
"! failures (429, 502, 503, 504, connection errors) with exponential back-off.
"! POST and PATCH are only repeated when the server cannot have processed the
"! request (429) or the caller sent an Idempotency-Key header.
CLASS zcl_rik_rest_client DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_retry_policy,
        max_attempts  TYPE i,
        base_delay_ms TYPE i,
        max_delay_ms  TYPE i,
      END OF ty_retry_policy.

    CONSTANTS c_idempotency_header TYPE string VALUE `Idempotency-Key`.

    METHODS constructor
      IMPORTING base_url       TYPE string
                transport      TYPE REF TO zif_rik_http_transport OPTIONAL
                token_provider TYPE REF TO zif_rik_token_provider OPTIONAL
                retry_policy   TYPE ty_retry_policy               OPTIONAL
                clock          TYPE REF TO zif_rik_clock          OPTIONAL.

    "! Sends a request; raises for HTTP status >= 400 unless raise_on_error is off
    METHODS execute
      IMPORTING method          TYPE string
                path            TYPE string
                body            TYPE string                            OPTIONAL
                headers         TYPE zif_rik_http_transport=>ty_headers OPTIONAL
                raise_on_error  TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(response) TYPE zif_rik_http_transport=>ty_response
      RAISING   zcx_rik_error.

    "! Serialises payload to camelCase JSON and sends it
    METHODS send_json
      IMPORTING method          TYPE string
                path            TYPE string
                payload         TYPE any
                headers         TYPE zif_rik_http_transport=>ty_headers OPTIONAL
                raise_on_error  TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(response) TYPE zif_rik_http_transport=>ty_response
      RAISING   zcx_rik_error.

  PRIVATE SECTION.
    DATA base_url       TYPE string.
    DATA transport      TYPE REF TO zif_rik_http_transport.
    DATA token_provider TYPE REF TO zif_rik_token_provider.
    DATA retry_policy   TYPE ty_retry_policy.
    DATA clock          TYPE REF TO zif_rik_clock.

    METHODS set_authorization
      CHANGING request TYPE zif_rik_http_transport=>ty_request
      RAISING  zcx_rik_error.

    METHODS may_retry
      IMPORTING request       TYPE zif_rik_http_transport=>ty_request
                attempt       TYPE i
                status        TYPE i OPTIONAL
      RETURNING VALUE(result) TYPE abap_bool.

    METHODS is_retryable_status
      IMPORTING status        TYPE i
      RETURNING VALUE(result) TYPE abap_bool.

    METHODS backoff_ms
      IMPORTING attempt       TYPE i
      RETURNING VALUE(result) TYPE i.

    METHODS retry_after_ms
      IMPORTING response      TYPE zif_rik_http_transport=>ty_response
                attempt       TYPE i
      RETURNING VALUE(result) TYPE i.

    METHODS header_value
      IMPORTING headers       TYPE zif_rik_http_transport=>ty_headers
                name          TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zcl_rik_rest_client IMPLEMENTATION.

  METHOD constructor.
    me->base_url       = base_url.
    me->transport      = COND #( WHEN transport IS BOUND THEN transport ELSE NEW zcl_rik_http_transport( ) ).
    me->token_provider = token_provider.
    me->clock          = COND #( WHEN clock IS BOUND THEN clock ELSE NEW zcl_rik_system_clock( ) ).
    me->retry_policy   = retry_policy.
    IF me->retry_policy-max_attempts IS INITIAL.
      me->retry_policy-max_attempts = 3.
    ENDIF.
    IF me->retry_policy-base_delay_ms IS INITIAL.
      me->retry_policy-base_delay_ms = 500.
    ENDIF.
    IF me->retry_policy-max_delay_ms IS INITIAL.
      me->retry_policy-max_delay_ms = 8000.
    ENDIF.
  ENDMETHOD.


  METHOD execute.
    DATA(request) = VALUE zif_rik_http_transport=>ty_request( method  = to_upper( method )
                                                              url     = base_url && path
                                                              headers = headers
                                                              body    = body ).
    IF header_value( headers = request-headers name = `Accept` ) IS INITIAL.
      APPEND VALUE #( name = `Accept` value = `application/json` ) TO request-headers.
    ENDIF.

    DATA(token_refreshed) = abap_false.
    DATA(attempt) = 0.

    DO.
      attempt += 1.
      set_authorization( CHANGING request = request ).

      TRY.
          response = transport->send( request ).
        CATCH zcx_rik_error INTO DATA(transport_error).
          IF transport_error->transient = abap_true AND may_retry( request = request attempt = attempt ).
            clock->wait( backoff_ms( attempt ) ).
            CONTINUE.
          ENDIF.
          RAISE EXCEPTION transport_error.
      ENDTRY.

      " expired or revoked token: fetch a new one once, without counting it as a retry
      IF response-status_code = 401 AND token_provider IS BOUND AND token_refreshed = abap_false.
        token_provider->invalidate( ).
        token_refreshed = abap_true.
        attempt -= 1.
        CONTINUE.
      ENDIF.

      IF is_retryable_status( response-status_code ) = abap_true
         AND may_retry( request = request attempt = attempt status = response-status_code ) = abap_true.
        clock->wait( retry_after_ms( response = response attempt = attempt ) ).
        CONTINUE.
      ENDIF.

      EXIT.
    ENDDO.

    IF raise_on_error = abap_true AND response-status_code >= 400.
      RAISE EXCEPTION NEW zcx_rik_error(
        text          = |{ request-method } { path } failed with HTTP { response-status_code }: |
                     && substring( val = response-body len = nmin( val1 = strlen( response-body ) val2 = 200 ) )
        http_status   = response-status_code
        response_body = response-body ).
    ENDIF.
  ENDMETHOD.


  METHOD send_json.
    DATA(all_headers) = headers.
    IF header_value( headers = all_headers name = `Content-Type` ) IS INITIAL.
      APPEND VALUE #( name = `Content-Type` value = `application/json` ) TO all_headers.
    ENDIF.
    response = execute( method         = method
                        path           = path
                        body           = zcl_rik_json=>to_json( payload )
                        headers        = all_headers
                        raise_on_error = raise_on_error ).
  ENDMETHOD.


  METHOD set_authorization.
    CHECK token_provider IS BOUND.
    DELETE request-headers WHERE name = `Authorization`.
    APPEND VALUE #( name = `Authorization` value = token_provider->get_authorization( ) ) TO request-headers.
  ENDMETHOD.


  METHOD may_retry.
    IF attempt >= retry_policy-max_attempts.
      result = abap_false.
      RETURN.
    ENDIF.

    IF ( request-method = `POST` OR request-method = `PATCH` )
       AND status <> 429
       AND header_value( headers = request-headers name = c_idempotency_header ) IS INITIAL.
      result = abap_false.
      RETURN.
    ENDIF.

    result = abap_true.
  ENDMETHOD.


  METHOD is_retryable_status.
    result = xsdbool( status = 429 OR status = 502 OR status = 503 OR status = 504 ).
  ENDMETHOD.


  METHOD backoff_ms.
    result = nmin( val1 = retry_policy-base_delay_ms * ipow( base = 2 exp = attempt - 1 )
                   val2 = retry_policy-max_delay_ms ).
  ENDMETHOD.


  METHOD retry_after_ms.
    DATA(retry_after) = condense( header_value( headers = response-headers name = `Retry-After` ) ).
    IF retry_after IS NOT INITIAL AND retry_after CO '0123456789'.
      result = nmin( val1 = CONV i( retry_after ) * 1000 val2 = retry_policy-max_delay_ms ).
    ELSE.
      result = backoff_ms( attempt ).
    ENDIF.
  ENDMETHOD.


  METHOD header_value.
    " HTTP header names are case-insensitive
    LOOP AT headers INTO DATA(header) WHERE name IS NOT INITIAL.
      IF to_lower( header-name ) = to_lower( name ).
        result = header-value.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
