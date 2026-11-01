"! <p class="shorttext synchronized">REST integration kit: token provider</p>
INTERFACE zif_rik_token_provider
  PUBLIC.

  "! Value for the Authorization header, for example 'Bearer eyJ...'
  METHODS get_authorization
    RETURNING VALUE(result) TYPE string
    RAISING   zcx_rik_error.

  "! Forget the cached token, so the next call fetches a new one (after a 401)
  METHODS invalidate.

ENDINTERFACE.
