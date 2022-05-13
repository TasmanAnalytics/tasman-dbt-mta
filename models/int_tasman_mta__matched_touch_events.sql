--Sources:

with

event_attributes as (
    select * from {{ ref('dmn_touch_attributes') }}
),

conversion_events as (
    select * from {{ ref('dmn_conversion_events') }}
),

touch_rules as (
    select * from {{ ref('touch_rules') }}
),

taxonomy as (
    select * from {{ ref('taxonomy') }}
),

touch_rules_typed as ( -- maps rule parts to their attribute types and adds a bit used for validating that all parts of any rule are matched

    select
        touch_rules.*,
        taxonomy.type,
        power(2, touch_rules.part - 1) as bit

    from
        touch_rules
        inner join taxonomy on
            touch_rules.attribute = taxonomy.attribute
),

touch_rules_compiled as ( -- converts the value of the rule part predicate to the appropriate native type, for better performance

    select
        *,
        case
            when type = 'boolean' and value = 'true' then true
            when type = 'boolean' and value = 'false' then false
            else null
        end as boolean_value,

        case
            when type = 'integer' then cast(value as integer)
            else null
        end as integer_value,

        case
            when type = 'float' then cast(value as float64)
            else null
        end as float_value

    from
        touch_rules_typed
),

rules_bitsums as ( --calculates the sum of the of the bits per rule needed to validate that all parts per rule are satisfied.

    select
        model,
        category,
        rule,
        power(2, max(part)) - 1 as bitsum

    from
        touch_rules_typed

    group by
        model,
        category,
        rule

    order by
        model,
        category,
        rule
),

matched_parts as ( --returns all matched parts of the rules from the event stream (contains duplicates, handled downstreams.)

    select
        event_attributes.user_id,
        event_attributes.event_id,
        event_attributes.tstamp,
        event_attributes.attribute,
        event_attributes.value,
        rules.model,
        rules.category,
        rules.rule,
        rules.part,
        rules.bit

    from
        event_attributes
        inner join touch_rules_compiled as rules on
            event_attributes.attribute = rules.attribute

    where
        (rules.type = 'boolean'
            and (
                (rules.relation = '=' and event_attributes.value = 'true' and rules.boolean_value = true)
                or (rules.relation = '=' and event_attributes.value = 'false' and rules.boolean_value = false)
                )
        )

        or (rules.type = 'integer'
            and (
                 (rules.relation = '=' and safe_cast(event_attributes.value as integer) = rules.integer_value)
                 or (rules.relation = '>=' and safe_cast(event_attributes.value as integer) >= rules.integer_value)
                 or (rules.relation = '<=' and safe_cast(event_attributes.value as integer) <= rules.integer_value)
                 or (rules.relation = '>' and safe_cast(event_attributes.value as integer) > rules.integer_value)
                 or (rules.relation = '<' and safe_cast(event_attributes.value as integer) < rules.integer_value)
                 or (rules.relation = '<>' and safe_cast(event_attributes.value as integer) <> rules.integer_value)
                 )
        )

        or (rules.type = 'float'
            and (
                 (rules.relation = '=' and safe_cast(event_attributes.value as float64) = rules.float_value)
                 or (rules.relation = '>=' and safe_cast(event_attributes.value as float64) >= rules.float_value)
                 or (rules.relation = '<=' and safe_cast(event_attributes.value as float64) <= rules.float_value)
                 or (rules.relation = '>' and safe_cast(event_attributes.value as float64) > rules.float_value)
                 or (rules.relation = '<' and safe_cast(event_attributes.value as float64) < rules.float_value)
                 )
        )

        or (rules.type = 'string'
            and (
                 (rules.relation = '=' and event_attributes.value = rules.value)
                 or (rules.relation = '>=' and event_attributes.value >= rules.value)
                 or (rules.relation = '<=' and event_attributes.value <= rules.value)
                 or (rules.relation = '>' and event_attributes.value > rules.value)
                 or (rules.relation = '<' and event_attributes.value < rules.value)
                 or (rules.relation = '<>' and event_attributes.value <> rules.value)
                 )
        )
),

matched_rules as ( -- returns fulfilled rules which indicates that an event matches a touch category

    select
        matched_parts.user_id,
        matched_parts.event_id,
        matched_parts.tstamp,
        matched_parts.model,
        matched_parts.category,
        matched_parts.rule,
        sum(matched_parts.bit) as bits,
        rules_bitsums.bitsum

    from
        matched_parts
        inner join rules_bitsums on
            rules_bitsums.model = matched_parts.model
            and rules_bitsums.category = matched_parts.category
            and rules_bitsums.rule = matched_parts.rule

    group by
        matched_parts.user_id,
        matched_parts.event_id,
        matched_parts.tstamp,
        matched_parts.model,
        matched_parts.category,
        matched_parts.rule,
        rules_bitsums.bitsum

    having
        bits = rules_bitsums.bitsum
),

matched_categories as (-- Return one event record per category (for the case where an event matches multiple rules within a category)

    select distinct
        user_id,
        event_id,
        tstamp,
        model,
        category

    from
        matched_rules
),

conversions_after_touches as (

    select
        touches.user_id,
        touches.event_id as touch_event_id,
        touches.tstamp as touch_tstamp,
        touches.model,
        touches.category,
        conversions.event_id as conversion_event_id,
        conversions.tstamp as conversion_tstamp,
        conversions.conversion

    from
        matched_categories as touches
        left join conversion_events as conversions
            on
                touches.user_id = conversions.user_id
                and touches.model = conversions.model
                and touches.tstamp < conversions.tstamp
    where
        touches.user_id is not null
),

matched_touches as (

    select distinct
        user_id,
        touch_event_id,
        touch_tstamp,
        model,
        category,
        case
            when conversion is not null
            then first_value(conversion_event_id) over (partition by user_id, touch_event_id, model, category order by conversion_tstamp rows unbounded preceding)
        end as conversion_event_id,
        case
            when conversion is not null
            then first_value(conversion_tstamp) over (partition by user_id, touch_event_id, model, category order by conversion_tstamp rows unbounded preceding)
        end as conversion_tstamp,
        case
            when conversion is not null
            then first_value(conversion) over (partition by user_id, touch_event_id, model, category order by conversion_tstamp rows unbounded preceding)
        end as conversion

    from
        conversions_after_touches
),

touch_events as (

    select
        user_id,
        touch_event_id as event_id,
        touch_tstamp as timestamp,
        model,
        category,
        conversion,
        conversion_event_id,
        conversion_tstamp,
        case
            when conversion is not null
            then rank() over (partition by conversion_event_id, model order by touch_tstamp)
        end as convert_seq_up,
        case
            when conversion is not null
            then rank() over (partition by conversion_event_id, model order by touch_tstamp desc)
        end as convert_seq_down,
        case
            when conversion is not null
            then date_diff(touch_tstamp, lag(touch_tstamp) over (partition by conversion_event_id, model order by touch_tstamp), second)
        end as interval_pre,
        -- in bigquery, we cannot fallback on conversion_tstamp as default_value for the lead() function, as BQ requires the default_expression to be a constant.
        -- since we have the interval_convert, no need to fallback on conversion_tstamp: interval_post will be null if there is no later touch (same logic as interval_pre).
        case
            when conversion is not null
            then date_diff(lead(touch_tstamp, 1) over (partition by conversion_event_id, model order by touch_tstamp), touch_tstamp, second)
        end as interval_post,
        case
            when conversion is not null
            then date_diff(conversion_tstamp, touch_tstamp, second)
        end as interval_convert

    from
        matched_touches
)

select * from touch_events
