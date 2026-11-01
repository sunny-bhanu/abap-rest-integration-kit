"! <p class="shorttext synchronized">REST integration kit: HTTP transport</p>
"! The only place that talks to the network. Everything above it (token
"! handling, retries, JSON) is plain ABAP and unit-testable with a double.
INTERFACE zif_rik_http_transport
  PUBLIC.

  TYPES:
    BEGIN OF ty_header,
      name  TYPE string,
      value TYPE string,
    END OF ty_header,
    ty_headers TYPE STANDARD TABLE OF ty_header WITH EMPTY KEY,

    BEGIN OF ty_request,
      method  TYPE string,
      url     TYPE string,
      headers TYPE ty_headers,
      body    TYPE string,
    END OF ty_request,

    BEGIN OF ty_response,
      status_code TYPE i,
      reason      TYPE string,
      headers     TYPE ty_headers,
      body        TYPE string,
    END OF ty_response.

  "! Sends one request. HTTP error statuses are returned, not raised;
  "! only connection problems raise (with transient = abap_true).
  METHODS send
    IMPORTING request         TYPE ty_request
    RETURNING VALUE(response) TYPE ty_response
    RAISING   zcx_rik_error.

ENDINTERFACE.
