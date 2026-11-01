CLASS ltc_response_builder DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS all_success_gives_s_and_200   FOR TESTING RAISING cx_static_check.
    METHODS errors_are_consolidated       FOR TESTING RAISING cx_static_check.
    METHODS empty_request_is_failure      FOR TESTING RAISING cx_static_check.
    METHODS json_uses_camel_case          FOR TESTING RAISING cx_static_check.
    METHODS demo_processor_end_to_end     FOR TESTING RAISING cx_static_check.
ENDCLASS.


CLASS ltc_response_builder IMPLEMENTATION.

  METHOD all_success_gives_s_and_200.
    DATA(builder) = NEW zcl_rik_response_builder( ).
    builder->add_success( reference = `A` sap_key = `100` )->add_success( reference = `B` sap_key = `101` ).

    DATA(response) = builder->build( ).
    cl_abap_unit_assert=>assert_equals( exp = 'S' act = response-status ).
    cl_abap_unit_assert=>assert_equals( exp = 2   act = response-succeeded ).
    cl_abap_unit_assert=>assert_equals( exp = 200 act = builder->http_status( ) ).
  ENDMETHOD.


  METHOD errors_are_consolidated.
    DATA(builder) = NEW zcl_rik_response_builder( ).
    builder->add_success( reference = `A` ).
    builder->add_error( reference = `B` field = `plant`    text = `Plant is required` ).
    builder->add_error( reference = `B` field = `quantity` text = `Quantity must be greater than zero` ).
    builder->add_success( reference = `B` ).  " must not turn B into a success

    DATA(response) = builder->build( ).
    cl_abap_unit_assert=>assert_equals( exp = 'F' act = response-status ).
    cl_abap_unit_assert=>assert_equals( exp = 2   act = response-total ).
    cl_abap_unit_assert=>assert_equals( exp = 1   act = response-failed ).
    cl_abap_unit_assert=>assert_equals( exp = 2   act = lines( response-records[ reference = `B` ]-messages ) ).
    cl_abap_unit_assert=>assert_equals( exp = 422 act = builder->http_status( ) ).
  ENDMETHOD.


  METHOD empty_request_is_failure.
    DATA(response) = NEW zcl_rik_response_builder( )->build( ).
    cl_abap_unit_assert=>assert_equals( exp = 'F' act = response-status ).
  ENDMETHOD.


  METHOD json_uses_camel_case.
    DATA(json) = NEW zcl_rik_response_builder( )->add_success( reference = `A` sap_key = `100` )->to_json( ).
    cl_abap_unit_assert=>assert_char_cp( exp = '*"sapKey":"100"*' act = json ).
    cl_abap_unit_assert=>assert_char_cp( exp = '*"succeeded":1*'  act = json ).
  ENDMETHOD.


  METHOD demo_processor_end_to_end.
    DATA(builder) = NEW zcl_rik_response_builder( ).
    DATA(processor) = CAST zif_rik_inbound_processor( NEW zcl_rik_demo_item_processor( ) ).

    processor->process(
      payload = `{"items":[`
             && `{"reference":"EXT-1","material":"M-100","plant":"1000","quantity":5,"unit":"EA"},`
             && `{"reference":"EXT-2","material":"","plant":"1000","quantity":0,"unit":"EA"}]}`
      builder = builder ).

    DATA(response) = builder->build( ).
    cl_abap_unit_assert=>assert_equals( exp = 'F' act = response-status ).
    cl_abap_unit_assert=>assert_equals( exp = 'S' act = response-records[ reference = `EXT-1` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 2   act = lines( response-records[ reference = `EXT-2` ]-messages ) ).
  ENDMETHOD.

ENDCLASS.
