-- user3 has two conversions under w_shaped_30_days: a lead (da9360ef) and a purchase (be62daba).
-- The share_attribution partition is per-conversion, so each conversion independently
-- distributes its spec shares. This test pins that the purchase conversion is attributed
-- to the last touch (dff554e6, direct) under spec 3 (convert_seq_down=1, purchase).
--
-- Spec 3 share = 0.3. Only one touch matches spec 3 (last touch), so conversion_share = 0.3.

select * from {{ ref('tasman_mta__attributed_conversions') }}

where
    --filter criteria: user3's purchase under w_shaped_30_days, spec 3 share
    conversion_event_id = 'be62daba-e4d2-4998-a057-8a3b25f2e9e3'
    and model_id = 'w_shaped_30_days'
    and spec = 3
    and conversion_share = 0.3

    --success criteria: attributed to last touch (direct channel)
    and not (
        touch_event_id = 'dff554e6-2f53-4eb1-a663-70d33658be63'
        and touch_user_id = 'user3@tasman.ai'
        and convert_seq_down = 1
        and conversion_category = 'purchase'
        and touch_category = 'all_channels'
    )
