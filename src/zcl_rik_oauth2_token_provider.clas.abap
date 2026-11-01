"! <p class="shorttext synchronized">REST integration kit: OAuth 2.0 client-credentials token</p>
"! Fetches a token once and caches it until shortly before it expires.
"! Prefer a destination / communication arrangement with OAuth 2.0 where the
"! platform handles tokens; use this class where that is not available.
CLASS zcl_rik_oauth2_token_provider DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rik_token_provider.

    TYPES:
      BEGIN OF ty_config,
        token_url                TYPE string,
        client_id                TYPE string,
        client_secret            TYPE string,
        scope                    TYPE string,
        "! Renew this many seconds before the real expiry (default 60)
        expiry_skew_seconds      TYPE i,
        "! Lifetime to assume when the server sends no expires_in (default 900)
        default_lifetime_seconds TYPE i,
      END OF ty_config.

    METHODS constructor
      IMPORTING config    TYPE ty_config
                transport TYPE REF TO zif_rik_http_transport OPTIONAL
                clock     TYPE REF TO zif_rik_clock          OPTIONAL.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_token_response,
        access_token TYPE string,
        token_type   TYPE string,
        expires_in   TYPE i,
      END OF ty_token_response.

    DATA config       TYPE ty_config.
    DATA transport    TYPE REF TO zif_rik_http_transport.
    DATA clock        TYPE REF TO zif_rik_clock.
    DATA access_token TYPE string.
    DATA token_type   TYPE string.
    DATA expires_at   TYPE utclong.

    METHODS request_token
      RAISING zcx_rik_error.

    METHODS form_body
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zcl_rik_oauth2_token_provider IMPLEMENTATION.

  METHOD constructor.
    me->config = config.
    IF me->config-expiry_skew_seconds IS INITIAL.
      me->config-expiry_skew_seconds = 60.
    ENDIF.
    IF me->config-default_lifetime_seconds IS INITIAL.
      me->config-default_lifetime_seconds = 900.
    ENDIF.
    me->transport = COND #( WHEN transport IS BOUND THEN transport ELSE NEW zcl_rik_http_transport( ) ).
    me->clock     = COND #( WHEN clock IS BOUND THEN clock ELSE NEW zcl_rik_system_clock( ) ).
  ENDMETHOD.


  METHOD zif_rik_token_provider~get_authorization.
    IF access_token IS INITIAL OR clock->now( ) >= expires_at.
      request_token( ).
    ENDIF.
    result = |{ token_type } { access_token }|.
  ENDMETHOD.


  METHOD zif_rik_token_provider~invalidate.
    CLEAR: access_token, expires_at.
  ENDMETHOD.


  METHOD request_token.
    DATA(response) = transport->send( VALUE #(
      method  = `POST`
      url     = config-token_url
      headers = VALUE #( ( name = `Content-Type` value = `application/x-www-form-urlencoded` )
                         ( name = `Accept`       value = `application/json` ) )
      body    = form_body( ) ) ).

    IF response-status_code <> 200.
      RAISE EXCEPTION NEW zcx_rik_error( text          = |Token request failed with HTTP { response-status_code }|
                                         http_status   = response-status_code
                                         response_body = response-body ).
    ENDIF.

    DATA token TYPE ty_token_response.
    zcl_rik_json=>from_json( EXPORTING json        = response-body
                                       pretty_name = /ui2/cl_json=>pretty_mode-low_case
                             CHANGING  data        = token ).

    IF token-access_token IS INITIAL.
      RAISE EXCEPTION NEW zcx_rik_error( text = `Token response contains no access_token` ).
    ENDIF.

    access_token = token-access_token.
    token_type   = COND #( WHEN token-token_type IS INITIAL OR to_upper( token-token_type ) = `BEARER`
                           THEN `Bearer` ELSE token-token_type ).

    DATA(lifetime) = COND i( WHEN token-expires_in > 0 THEN token-expires_in
                             ELSE config-default_lifetime_seconds ).
    expires_at = utclong_add( val     = clock->now( )
                              seconds = nmax( val1 = lifetime - config-expiry_skew_seconds val2 = 0 ) ).
  ENDMETHOD.


  METHOD form_body.
    result = |grant_type=client_credentials|
          && |&client_id={ escape( val = config-client_id format = cl_abap_format=>e_url_full ) }|
          && |&client_secret={ escape( val = config-client_secret format = cl_abap_format=>e_url_full ) }|.
    IF config-scope IS NOT INITIAL.
      result = result && |&scope={ escape( val = config-scope format = cl_abap_format=>e_url_full ) }|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
