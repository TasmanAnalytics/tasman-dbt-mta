{{
    config(
        materialized='table',
        snowflake_warehouse=get_warehouse()
    )
}}

with

touches as (
    select * from {{ ref('tasman_mta__filtered_touch_events') }}
),

conversions as (
    select * from {{ ref('tasman_mta__filtered_conversion_events') }}
),

attribution_rules as (
    select * from {{ var('attribution_rules') }}
),

conversion_shares as (
    select * from {{ var('conversion_shares') }}
),

attribution_windows as (
    select * from {{ var('attribution_windows') }}
),

-- For each conversion, find the timestamp of the immediately preceding conversion for the
-- same user and model. This timestamp is the "session start" — only touches after it are
-- considered fresh candidates for this conversion.
conversions_with_session_start as (

    select
        conversion_user_id,
        conversion_event_id,
        conversion_timestamp,
        model_id,
        conversion_category,
        lag(conversion_timestamp) over (
            partition by conversion_user_id, model_id
            order by conversion_timestamp
        ) as prev_conversion_timestamp

    from conversions

),

conversions_after_touches as (

    select
        touches.touch_user_id,
        touches.touch_event_id,
        touches.touch_timestamp,
        touches.model_id,
        touches.touch_category,
        conversions_with_session_start.conversion_event_id,
        conversions_with_session_start.conversion_timestamp,
        conversions_with_session_start.conversion_category,
        conversions_with_session_start.prev_conversion_timestamp,
        -- Count of touches that are "fresh" for this conversion (occurred after the preceding
        -- conversion). When zero, all touches fall back as candidates so the originating
        -- touchpoint still receives credit for consecutive conversions with no intervening touch.
        sum(case
            when conversions_with_session_start.prev_conversion_timestamp is null then 1
            when touches.touch_timestamp > conversions_with_session_start.prev_conversion_timestamp then 1
            else 0
        end) over (
            partition by touches.touch_user_id, conversions_with_session_start.conversion_event_id, touches.model_id
        ) as fresh_touch_count

    from
        touches
        inner join conversions_with_session_start
            on touches.touch_user_id = conversions_with_session_start.conversion_user_id
            and touches.model_id = conversions_with_session_start.model_id
            and touches.touch_timestamp < conversions_with_session_start.conversion_timestamp
    where
        touches.touch_user_id is not null

),

matched_touches as (

    select distinct
        touch_user_id,
        touch_event_id,
        touch_timestamp,
        model_id,
        touch_category,
        conversion_event_id,
        conversion_timestamp,
        conversion_category

    from conversions_after_touches

    where
        -- Fresh touch: occurred within the current attribution session
        (prev_conversion_timestamp is null or touch_timestamp > prev_conversion_timestamp)
        -- Fallback: no fresh touches exist, so carry the preceding touch forward
        or fresh_touch_count = 0

),

conversion_intervals as (
    select
        matched_touches.touch_user_id,
        matched_touches.touch_event_id,
        matched_touches.touch_timestamp,
        matched_touches.model_id,
        matched_touches.touch_category,
        matched_touches.conversion_category,
        matched_touches.conversion_event_id,
        matched_touches.conversion_timestamp,
        case
            when matched_touches.conversion_category is not null
            then {{ dbt.datediff("matched_touches.touch_timestamp", "matched_touches.conversion_timestamp", 'second') }}
        end as interval_convert,
        attribution_windows.att_window,
        attribution_windows.time_seconds

    from
        matched_touches
    inner join
        attribution_windows
        on matched_touches.model_id = attribution_windows.model_id

),

windowed_touches as (
    select
        *
    from
        conversion_intervals
    where
        interval_convert < time_seconds
        or time_seconds = 0

),

touch_events as (

    select
        touch_user_id,
        touch_event_id,
        touch_timestamp,
        model_id,
        touch_category,
        conversion_category,
        conversion_event_id,
        conversion_timestamp,
        att_window,
        interval_convert,
        case
            when conversion_category is not null
            then {{ dbt.datediff("lag(touch_timestamp) over (partition by conversion_event_id, model_id order by touch_timestamp)", "touch_timestamp", 'second') }}
        end as interval_pre,
        case
            when conversion_category is not null
            then {{ dbt.datediff("touch_timestamp", "coalesce(lead(touch_timestamp, 1) over (partition by conversion_event_id, model_id order by touch_timestamp), conversion_timestamp)", 'second') }}
        end as interval_post,
        case
            when conversion_category is not null
            then count(distinct touch_event_id) over (partition by conversion_event_id, model_id)
        end as convert_touch_count,
        case
            when conversion_category is not null
            then rank() over (partition by conversion_event_id, model_id order by touch_timestamp)
        end as convert_seq_up,
        case
            when conversion_category is not null
            then rank() over (partition by conversion_event_id, model_id order by touch_timestamp desc)
        end as convert_seq_down,
        case
            when conversion_category is not null
            then rank() over (partition by touch_user_id, model_id order by conversion_timestamp)
        end as conversion_number

    from
        windowed_touches
),

touch_taxonomy as (

    select 'touch_category' as attribute union all
    select 'conversion_category' as attribute union all
    select 'convert_touch_count' as attribution union all
    select 'convert_seq_up' as attribute union all
    select 'convert_seq_down' as attribute union all
    select 'interval_pre' as attribute union all
    select 'interval_post' as attribute union all
    select 'interval_convert' as attribute

),

touch_attributes as (

    select
        touch_events.touch_user_id,
        touch_events.touch_event_id,
        touch_events.conversion_event_id,
        touch_events.model_id,
        touch_taxonomy.attribute,

        case
            when touch_taxonomy.attribute = 'touch_category' then cast(touch_events.touch_category as string)
            when touch_taxonomy.attribute = 'conversion_category' then cast(touch_events.conversion_category as string)
            when touch_taxonomy.attribute = 'convert_seq_up' then cast(touch_events.convert_seq_up as string)
            when touch_taxonomy.attribute = 'convert_seq_down' then cast(touch_events.convert_seq_down as string)
            when touch_taxonomy.attribute = 'interval_pre' then cast(touch_events.interval_pre as string)
            when touch_taxonomy.attribute = 'interval_post' then cast(touch_events.interval_post as string)
            when touch_taxonomy.attribute = 'interval_convert' then cast(touch_events.interval_convert as string)
        end as value

    from touch_events, touch_taxonomy
),

attribution_parts as (

    select
        attribution_rules.*,
        power(2, attribution_rules.part - 1) as bit

    from
        attribution_rules
),

rules_bitsums as (

    select
        model_id,
        spec,
        rule,
        power(2, max(part)) - 1 as bitsum

    from
        attribution_parts

    group by
        model_id,
        spec,
        rule

    order by
        model_id,
        spec,
        rule
),

matched_parts as (

    select
        touch_attributes.touch_user_id,
        touch_attributes.touch_event_id,
        touch_attributes.conversion_event_id,
        touch_attributes.attribute,
        touch_attributes.value,
        attribution_parts.model_id,
        attribution_parts.spec,
        attribution_parts.rule,
        attribution_parts.part,
        attribution_parts.bit

    from
        touch_attributes
        inner join attribution_parts on
            touch_attributes.attribute = attribution_parts.attribute
            and touch_attributes.model_id = attribution_parts.model_id

    where
        (attribution_parts.relation = '=' and touch_attributes.value = cast(attribution_parts.value as string))
        or (attribution_parts.relation = '>=' and touch_attributes.value >= cast(attribution_parts.value as string))
        or (attribution_parts.relation = '<=' and touch_attributes.value <= cast(attribution_parts.value as string))
        or (attribution_parts.relation = '>' and touch_attributes.value > cast(attribution_parts.value as string))
        or (attribution_parts.relation = '<' and touch_attributes.value < cast(attribution_parts.value as string))
        or (attribution_parts.relation = '<>' and touch_attributes.value <> cast(attribution_parts.value as string))
),

matched_rules as (

    select
        matched_parts.touch_user_id,
        matched_parts.touch_event_id,
        matched_parts.conversion_event_id,
        matched_parts.model_id,
        matched_parts.spec,
        matched_parts.rule,
        sum(matched_parts.bit) as bits,
        rules_bitsums.bitsum

    from
        matched_parts
        inner join rules_bitsums on
            matched_parts.model_id = rules_bitsums.model_id
            and matched_parts.spec = rules_bitsums.spec
            and matched_parts.rule = rules_bitsums.rule

    group by
        matched_parts.touch_user_id,
        matched_parts.touch_event_id,
        matched_parts.conversion_event_id,
        matched_parts.model_id,
        matched_parts.spec,
        matched_parts.rule,
        rules_bitsums.bitsum

    having
        bits = rules_bitsums.bitsum
),

matched_groups as (

    select distinct
        touch_user_id,
        touch_event_id,
        conversion_event_id,
        model_id,
        spec

    from
        matched_rules
),

share_attribution as (

    select
        matched_groups.touch_user_id,
        matched_groups.touch_event_id,
        matched_groups.conversion_event_id,
        matched_groups.model_id,
        matched_groups.spec,
        conversion_shares.share / count(matched_groups.touch_event_id) over (partition by matched_groups.touch_user_id, matched_groups.conversion_event_id, matched_groups.model_id, matched_groups.spec) as conversion_share

    from
        matched_groups
        inner join conversion_shares on
            matched_groups.model_id = conversion_shares.model_id
            and matched_groups.spec = conversion_shares.spec
),

attributed_events as (
    select
        {{ generate_surrogate_key([
            'touch_events.model_id',
            'touch_events.touch_event_id',
            'touch_events.conversion_event_id',
            'share_attribution.spec'
            ]) }} as surrogate_key,
        touch_events.*,
        share_attribution.spec,
        share_attribution.conversion_share

    from
        touch_events
        left join share_attribution on
            touch_events.touch_event_id = share_attribution.touch_event_id
            and touch_events.conversion_event_id = share_attribution.conversion_event_id
            and touch_events.model_id = share_attribution.model_id
)


select * from attributed_events
