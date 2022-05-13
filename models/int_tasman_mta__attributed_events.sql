with

touch_events as (
    select * from {{ ref('dmn_touch_events') }}
),

attribution_rules as (
    select * from {{ ref('attribution_rules') }}
),

conversion_shares as (
    select * from {{ ref('conversion_shares') }}
),

touch_taxonomy as (

    select 'category' as attribute union all
    select 'conversion' as attribute union all
    select 'convert_seq_up' as attribute union all
    select 'convert_seq_down' as attribute union all
    select 'interval_pre' as attribute union all
    select 'interval_post' as attribute union all
    select 'interval_convert' as attribute

),

touch_attributes as (

    select
        touch_events.user_id,
        touch_events.event_id,
        touch_events.conversion_event_id,
        touch_events.model,
        touch_taxonomy.attribute,

        case
            when touch_taxonomy.attribute = 'category' then touch_events.category
            when touch_taxonomy.attribute = 'conversion' then touch_events.conversion
            when touch_taxonomy.attribute = 'convert_seq_up' then touch_events.convert_seq_up
            when touch_taxonomy.attribute = 'convert_seq_down' then touch_events.convert_seq_down
            when touch_taxonomy.attribute = 'interval_pre' then touch_events.interval_pre
            when touch_taxonomy.attribute = 'interval_post' then touch_events.interval_post
            when touch_taxonomy.attribute = 'interval_convert' then touch_events.interval_convert
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
        model,
        spec,
        rule,
        power(2, max(part)) - 1 as bitsum

    from
        attribution_parts

    group by
        model,
        spec,
        rule

    order by
        model,
        spec,
        rule
),

matched_parts as (

    select
        touch_attributes.user_id,
        touch_attributes.event_id,
        touch_attributes.conversion_event_id,
        touch_attributes.attribute,
        touch_attributes.value,
        attribution_parts.model,
        attribution_parts.spec,
        attribution_parts.rule,
        attribution_parts.part,
        attribution_parts.bit

    from
        touch_attributes
        inner join attribution_parts on
            touch_attributes.attribute = attribution_parts.attribute
            and touch_attributes.model = attribution_parts.model

    where
        (attribution_parts.relation = '=' and touch_attributes.value = attribution_parts.value)
        or (attribution_parts.relation = '>=' and touch_attributes.value >= attribution_parts.value)
        or (attribution_parts.relation = '<=' and touch_attributes.value <= attribution_parts.value)
        or (attribution_parts.relation = '>' and touch_attributes.value > attribution_parts.value)
        or (attribution_parts.relation = '<' and touch_attributes.value < attribution_parts.value)
        or (attribution_parts.relation = '<>' and touch_attributes.value <> attribution_parts.value)
),

matched_rules as (

    select
        matched_parts.user_id,
        matched_parts.event_id,
        matched_parts.conversion_event_id,
        matched_parts.model,
        matched_parts.spec,
        matched_parts.rule,
        sum(matched_parts.bit) as bits,
        rules_bitsums.bitsum

    from
        matched_parts
        inner join rules_bitsums on
            matched_parts.model = rules_bitsums.model
            and matched_parts.spec = rules_bitsums.spec
            and matched_parts.rule = rules_bitsums.rule

    group by
        matched_parts.user_id,
        matched_parts.event_id,
        matched_parts.conversion_event_id,
        matched_parts.model,
        matched_parts.spec,
        matched_parts.rule,
        rules_bitsums.bitsum

    having
        bits = rules_bitsums.bitsum
),

matched_groups as (

    select distinct
        user_id,
        event_id,
        conversion_event_id,
        model,
        spec

    from
        matched_rules
),

share_attribution as (

    select
        matched_groups.user_id,
        matched_groups.event_id,
        matched_groups.model,
        matched_groups.spec,
        conversion_shares.share / count(1) over (partition by matched_groups.user_id, matched_groups.conversion_event_id, matched_groups.model, matched_groups.spec) as conversion_share

    from
        matched_groups
        inner join conversion_shares on
            matched_groups.model = conversion_shares.model
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
            touch_events.event_id = share_attribution.event_id
            and touch_events.model = share_attribution.model
)


select * from attributed_events
