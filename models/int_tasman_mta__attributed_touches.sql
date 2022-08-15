{{ config(materialized='table') }}

with

touches as (
    select * from {{ ref('int_tasman_mta__filtered_touch_events') }}
),

conversions as (
    select * from {{ ref('int_tasman_mta__filtered_conversion_events') }}
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

conversions_after_touches as (

    select
        touches.touch_segmentation_id,
        touches.touch_event_id,
        touches.touch_timestamp,
        touches.model_id,
        touches.touch_category,
        conversions.conversion_event_id,
        conversions.conversion_timestamp,
        conversions.conversion_category

    from
        touches
        inner join conversions
            on
                touches.touch_segmentation_id = conversions.conversion_segmentation_id
                and touches.model_id = conversions.model_id
                and touches.touch_timestamp < conversions.conversion_timestamp
    where
        touches.touch_segmentation_id is not null
),

matched_touches as (

    select distinct
        touch_segmentation_id,
        touch_event_id,
        touch_timestamp,
        model_id,
        touch_category,
        case
            when conversion_category is not null
            then first_value(conversion_event_id) over (partition by touch_segmentation_id, touch_event_id, model_id, touch_category order by conversion_timestamp rows unbounded preceding)
        end as conversion_event_id,
        case
            when conversion_category is not null
            then first_value(conversion_timestamp) over (partition by touch_segmentation_id, touch_event_id, model_id, touch_category order by conversion_timestamp rows unbounded preceding)
        end as conversion_timestamp,
        case
            when conversion_category is not null
            then first_value(conversion_category) over (partition by touch_segmentation_id, touch_event_id, model_id, touch_category order by conversion_timestamp rows unbounded preceding)
        end as conversion_category

    from
        conversions_after_touches
),

conversion_intervals as (
    select
        matched_touches.touch_segmentation_id,
        matched_touches.touch_event_id,
        matched_touches.touch_timestamp,
        matched_touches.model_id,
        matched_touches.touch_category,
        matched_touches.conversion_category,
        matched_touches.conversion_event_id,
        matched_touches.conversion_timestamp,
        case
            when matched_touches.conversion_category is not null
            then {{ dbt_utils.datediff("matched_touches.touch_timestamp", "matched_touches.conversion_timestamp", 'second') }}
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
        touch_segmentation_id,
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
            then {{ dbt_utils.datediff("lag(touch_timestamp) over (partition by conversion_event_id, model_id order by touch_timestamp)", "touch_timestamp", 'second') }}
        end as interval_pre,
        case
            when conversion_category is not null
            then {{ dbt_utils.datediff("touch_timestamp", "coalesce(lead(touch_timestamp, 1) over (partition by conversion_event_id, model_id order by touch_timestamp), conversion_timestamp)", 'second') }}
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
        end as convert_seq_down
        

    from
        windowed_touches
),

touch_taxonomy as (

    select 'touch_category' as attribute union all
    select 'conversion' as attribute union all
    select 'convert_touch_count' as attribution union all
    select 'convert_seq_up' as attribute union all
    select 'convert_seq_down' as attribute union all
    select 'interval_pre' as attribute union all
    select 'interval_post' as attribute union all
    select 'interval_convert' as attribute

),

touch_attributes as (

    select
        touch_events.touch_segmentation_id,
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
        touch_attributes.touch_segmentation_id,
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
        matched_parts.touch_segmentation_id,
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
        matched_parts.touch_segmentation_id,
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
        touch_segmentation_id,
        touch_event_id,
        conversion_event_id,
        model_id,
        spec

    from
        matched_rules
),

share_attribution as (

    select
        matched_groups.touch_segmentation_id,
        matched_groups.touch_event_id,
        matched_groups.model_id,
        matched_groups.spec,
        conversion_shares.share / count(1) over (partition by matched_groups.touch_segmentation_id, matched_groups.conversion_event_id, matched_groups.model_id, matched_groups.spec) as conversion_share

    from
        matched_groups
        inner join conversion_shares on
            matched_groups.model_id = conversion_shares.model_id
            and matched_groups.spec = conversion_shares.spec
),

attributed_events as (
    select
        touch_events.*,
        share_attribution.spec,
        share_attribution.conversion_share

    from
        touch_events
        left join share_attribution on
            touch_events.touch_event_id = share_attribution.touch_event_id
            and touch_events.model_id = share_attribution.model_id
)


select * from attributed_events