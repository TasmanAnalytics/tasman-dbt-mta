select * from {{ ref('tasman_mta__attributed_conversions') }}

where
    --filter criteria
    conversion_event_id = '739982bb-f169-40d0-814d-ff633db562c0'
    and model_id = 'first_touch_7_day'
    and conversion_share = 1

    --success criteria
    and not (
        touch_event_id = 'cb3a11ab-61ae-4e09-a1c6-8a49c44aa6ae'
        or touch_segmentation_id = 'user1@tasman.ai'
        or convert_touch_count = 3
        or convert_seq_up = 1
        or convert_seq_down = 3
        or conversion_category = 'purchase'
        or touch_category = 'all_channels'
    )
