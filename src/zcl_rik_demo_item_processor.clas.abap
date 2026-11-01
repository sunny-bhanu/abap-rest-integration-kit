"! <p class="shorttext synchronized">REST integration kit: demo inbound processor</p>
"! Example processor for a payload of items:
"! { "items": [ { "reference": "EXT-1001", "material": "M-100", "plant": "1000",
"!               "quantity": 5, "unit": "EA" } ] }
"! It collects every validation error per item. A real processor would post
"! the valid items through a released API or BAPI and return the SAP key.
CLASS zcl_rik_demo_item_processor DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rik_inbound_processor.

    TYPES:
      BEGIN OF ty_item,
        reference TYPE string,
        material  TYPE string,
        plant     TYPE string,
        quantity  TYPE decfloat34,
        unit      TYPE string,
      END OF ty_item,
      ty_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY,
      BEGIN OF ty_payload,
        items TYPE ty_items,
      END OF ty_payload.
ENDCLASS.



CLASS zcl_rik_demo_item_processor IMPLEMENTATION.

  METHOD zif_rik_inbound_processor~process.
    DATA request TYPE ty_payload.
    zcl_rik_json=>from_json( EXPORTING json = payload CHANGING data = request ).

    IF request-items IS INITIAL.
      RAISE EXCEPTION NEW zcx_rik_error( text = `Payload contains no items` http_status = 400 ).
    ENDIF.

    LOOP AT request-items INTO DATA(item).
      DATA(line) = sy-tabix.
      DATA(reference) = COND string( WHEN item-reference IS NOT INITIAL THEN item-reference
                                     ELSE |line { line }| ).

      IF item-reference IS INITIAL.
        builder->add_error( reference = reference field = `reference` text = `Reference is required` ).
      ENDIF.
      IF item-material IS INITIAL.
        builder->add_error( reference = reference field = `material` text = `Material is required` ).
      ENDIF.
      IF item-plant IS INITIAL.
        builder->add_error( reference = reference field = `plant` text = `Plant is required` ).
      ENDIF.
      IF item-quantity <= 0.
        builder->add_error( reference = reference field = `quantity` text = `Quantity must be greater than zero` ).
      ENDIF.
      IF item-unit IS INITIAL.
        builder->add_error( reference = reference field = `unit` text = `Unit is required` ).
      ENDIF.

      " add_success is ignored for references that already have errors
      builder->add_success( reference = reference
                            sap_key   = |{ item-plant }/{ item-material }|
                            message   = `Validated` ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
