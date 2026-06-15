select * from {{ ref('tasman_mta__attributed_conversions') }}

where
    --filter criteria
    conversion_event_id = '739982bb-f169-40d0-814d-ff633db562c0'
    and model_id = 'first_touch'
    and conversion_share = 1

    --success criteria
    and not (
        touch_event_id = '3f6931bc-785c-46fa-b868-6cac0bac549e'
        and touch_user_id = 'user1@tasman.ai'
        and convert_touch_count = 5
        and convert_seq_up = 1
        and convert_seq_down = 5
        and conversion_category = 'purchase'
        and touch_category = 'all_channels'
    )
