select * from {{ ref('tasman_mta__attributed_conversions') }}

where
    --filter criteria: user5's second conversion under first_touch model with full share
    conversion_event_id = '3olgh3bs-05hf-40bd-a5b8-2cfc77457904'
    and model_id = 'first_touch'
    and conversion_share = 1

    --success criteria: must be attributed to user5's earliest touch (paid-search 2024-09-10)
    and not (
        touch_event_id = '2ab3jfy0-7516-46d2-af13-fe0e309b997b'
        or touch_user_id = 'user5@tasman.ai'
        or convert_seq_up = 1
        or conversion_category = 'purchase'
        or touch_category = 'all_channels'
    )
