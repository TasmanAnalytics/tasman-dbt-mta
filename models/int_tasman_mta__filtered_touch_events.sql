{% if var('incremental') == 'true' %}
    {{config(materialized='incremental', schema='attribution')}}
{% else %}
    {{config(materialized='table', schema='attribution')}}
{% endif %}

with

touch_events as (
    select * from {{ var('touches_model') }}
    {% if is_incremental() %}
    -- this filter will only be applied on an incremental run
    where 
        {{var('touches_timestamp_field')}} > (select max(touch_timestamp) from {{ this }})
    {% endif %}
),

touch_rules as (
    select * from {{ var('touch_rules') }}
),

touch_attributes as (
    select distinct attribute from touch_rules
),

{%- set attributes_query -%}
        select distinct attribute from {{ var('touch_rules') }}
{%- endset -%}

{%- if execute -%}
    {% set attributes = run_query(attributes_query).rows %}
{%- else -%}
    {% set attributes = [] %}
{%- endif -%}

raw_event_attributes as (
    select
        touch_events.{{var('touches_event_id_field')}} as touch_event_id,
        touch_events.{{var('touches_timestamp_field')}} as touch_timestamp,
        touch_events.{{var('touches_segmentation_id_field')}} as touch_segmentation_id,
        touch_attributes.attribute as attribute,
        case
        {% for attribute in attributes -%}
            when touch_attributes.attribute = '{{ attribute[0] }}' then cast({{ attribute[0] }} as string)
        {% endfor %}
        end as value
    
    from
        touch_events,  touch_attributes

),

event_attributes as (
    select
        *
    from
        raw_event_attributes
    where
        value is not null
),

touch_rules_bit as ( -- maps rule parts to their attribute types and adds a bit used for validating that all parts of any rule are matched

    select
        *,
        power(2, part - 1) as bit

    from
        touch_rules
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
            when type = 'integer' then {{dbt.safe_cast("value", "integer")}}
            else null
        end as integer_value,
        case
            when type = 'float' then {{dbt.safe_cast("value", "numeric")}}
            else null
        end as float_value

    from
        touch_rules_bit
),

rules_bitsums as ( --calculates the sum of the of the bits per rule needed to validate that all parts per rule are satisfied.

    select
        model_id,
        touch_category,
        rule,
        power(2, max(part)) - 1 as bitsum

    from
        touch_rules_bit

    group by
        model_id,
        touch_category,
        rule

    order by
        model_id,
        touch_category,
        rule
),

matched_parts as ( --returns all matched parts of the rules from the event stream (contains duplicates, handled downstreams.)

    select
        event_attributes.touch_segmentation_id,
        event_attributes.touch_event_id,
        event_attributes.touch_timestamp,
        event_attributes.attribute,
        event_attributes.value,
        rules.model_id,
        rules.touch_category,
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
                 (rules.relation = '=' and {{dbt.safe_cast("event_attributes.value", "integer")}} = rules.integer_value)
                 or (rules.relation = '>=' and {{dbt.safe_cast("event_attributes.value", "integer")}} >= rules.integer_value)
                 or (rules.relation = '<=' and {{dbt.safe_cast("event_attributes.value", "integer")}} <= rules.integer_value)
                 or (rules.relation = '>' and {{dbt.safe_cast("event_attributes.value", "integer")}} > rules.integer_value)
                 or (rules.relation = '<' and {{dbt.safe_cast("event_attributes.value", "integer")}} < rules.integer_value)
                 or (rules.relation = '<>' and {{dbt.safe_cast("event_attributes.value", "integer")}} <> rules.integer_value)
                 )
        )

        or (rules.type = 'float'
            and (
                 (rules.relation = '=' and {{dbt.safe_cast("event_attributes.value", "numeric")}} = rules.float_value)
                 or (rules.relation = '>=' and {{dbt.safe_cast("event_attributes.value", "numeric")}} >= rules.float_value)
                 or (rules.relation = '<=' and {{dbt.safe_cast("event_attributes.value", "numeric")}} <= rules.float_value)
                 or (rules.relation = '>' and {{dbt.safe_cast("event_attributes.value", "numeric")}} > rules.float_value)
                 or (rules.relation = '<' and {{dbt.safe_cast("event_attributes.value", "numeric")}} < rules.float_value)
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

matched_rules as ( -- returns fulfilled rules which indicates that an event matches a touch touch_category

    select
        matched_parts.touch_segmentation_id,
        matched_parts.touch_event_id,
        matched_parts.touch_timestamp,
        matched_parts.model_id,
        matched_parts.touch_category,
        matched_parts.rule,
        sum(matched_parts.bit) as bits,
        rules_bitsums.bitsum

    from
        matched_parts
        inner join rules_bitsums on
            rules_bitsums.model_id = matched_parts.model_id
            and rules_bitsums.touch_category = matched_parts.touch_category
            and rules_bitsums.rule = matched_parts.rule

    group by
        matched_parts.touch_segmentation_id,
        matched_parts.touch_event_id,
        matched_parts.touch_timestamp,
        matched_parts.model_id,
        matched_parts.touch_category,
        matched_parts.rule,
        rules_bitsums.bitsum

    having
        bits = rules_bitsums.bitsum
),

matched_categories as (-- Return one event record per touch_category (for the case where an event matches multiple rules within a touch_category)

    select distinct
        touch_segmentation_id,
        touch_event_id,
        touch_timestamp,
        model_id,
        touch_category

    from
        matched_rules
)

select * from matched_categories
