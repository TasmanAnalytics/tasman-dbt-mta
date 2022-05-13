--Sources:

with

event_attributes as (
    select * from {{ ref('dmn_conversion_attributes') }}
),

conversion_rules as (
    select * from {{ ref('conversion_rules') }}
),

taxonomy as (
    select distinct attribute, type from {{ ref('taxonomy') }}
),

conversion_rules_typed as ( -- maps rule parts to their attribute types and adds a bit used for validating that all parts of any rule are matched

    select
        conversion_rules.*,
        taxonomy.type,
        power(2, conversion_rules.part - 1) as bit

    from
        conversion_rules
        inner join taxonomy on
            conversion_rules.attribute = taxonomy.attribute
),

conversion_rules_compiled as ( -- converts the value of the rule part predicate to the appropriate native type, for better performance

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
        conversion_rules_typed
),

rules_bitsums as ( --calculates the sum of the of the bits per rule needed to validate that all parts per rule are satisfied.

    select
        model,
        conversion,
        rule,
        power(2, max(part)) - 1 as bitsum

    from
        conversion_rules_typed

    group by
        model,
        conversion,
        rule

    order by
        model,
        conversion,
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
        rules.conversion,
        rules.rule,
        rules.part,
        rules.bit

    from
        event_attributes
        inner join conversion_rules_compiled as rules on
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

matched_rules as ( --returns fulfilled rules which indicates that a user has reached a conversion

    select
        matched_parts.user_id,
        matched_parts.event_id,
        matched_parts.tstamp,
        matched_parts.model,
        matched_parts.conversion,
        matched_parts.rule,
        sum(matched_parts.bit) as bits,
        rules_bitsums.bitsum

    from
        matched_parts
        inner join rules_bitsums on
            rules_bitsums.model = matched_parts.model
            and rules_bitsums.conversion = matched_parts.conversion
            and rules_bitsums.rule = matched_parts.rule

    group by
        matched_parts.user_id,
        matched_parts.event_id,
        matched_parts.tstamp,
        matched_parts.model,
        matched_parts.conversion,
        matched_parts.rule,
        rules_bitsums.bitsum

    having
        bits = rules_bitsums.bitsum
),

matched_conversions as (-- Returns the event_id and timestamp a user reached a certain conversion

    select distinct
        user_id,
        event_id,
        tstamp,
        model,
        conversion,
        rule

    from
        matched_rules
)

select * from matched_conversions