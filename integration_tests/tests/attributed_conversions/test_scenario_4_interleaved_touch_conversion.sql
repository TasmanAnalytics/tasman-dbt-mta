-- user6 journey: touch1(paid-search, Nov 1) → conv1(purchase, Nov 2) → touch2(organic, Nov 3) → conv2(purchase, Nov 4)
--
-- conv1 resets the attribution session. touch2 (organic-search, Nov 3) occurs after the
-- reset, so it is the only fresh candidate for conv2. touch1 (paid-search, Nov 1) occurred
-- before the reset and must NOT receive credit for conv2.
--
-- Under first_touch (convert_seq_up=1), conv2 should be attributed to touch2.

select * from {{ ref('tasman_mta__attributed_conversions') }}

where
    --filter criteria: user6's second purchase under first_touch model with full share
    conversion_event_id = 'a1b2c3d4-0020-0000-0000-000000000020'
    and model_id = 'first_touch'
    and conversion_share = 1

    --success criteria: attributed to touch2 (organic-search, Nov 3), not touch1
    and not (
        touch_event_id = 'a1b2c3d4-0002-0000-0000-000000000002'
        or touch_user_id = 'user6@tasman.ai'
        or convert_seq_up = 1
        or conversion_category = 'purchase'
        or touch_category = 'all_channels'
    )
