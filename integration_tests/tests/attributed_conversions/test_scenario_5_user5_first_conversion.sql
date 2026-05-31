-- Regression guard for user5's first conversion after the multi-conversion change.
-- user5: 3 touches (paid-search Sep 10, organic Sep 11, paid-search Sep 11) → conv1 (purchase Sep 12 11:31)
-- Under first_touch the earliest touch (paid-search Sep 10) must still receive full credit.

select * from {{ ref('tasman_mta__attributed_conversions') }}

where
    --filter criteria
    conversion_event_id = '3olgh3bs-05hf-40bd-a5b8-2cfc77457903'
    and model_id = 'first_touch'
    and conversion_share = 1

    --success criteria
    and not (
        touch_event_id = '2ab3jfy0-7516-46d2-af13-fe0e309b997b'
        or touch_user_id = 'user5@tasman.ai'
        or convert_seq_up = 1
        or conversion_category = 'purchase'
        or touch_category = 'all_channels'
    )
