{% if var('incremental') == 'true' %}
    {{config(materialized='incremental', schema='attribution')}}
{% else %}
    {{config(materialized='table', schema='attribution')}}
{% endif %}

with

conversion_events as (
    select * from {{ var('conversions_model') }}
    {% if is_incremental() %}
    -- this filter will only be applied on an incremental run
    where 
        {{var('conversions_timestamp_field')}} > (select max(conversion_timestamp) from {{ this }})
    {% endif %}
),

conversion_rules as (
    select * from {{ var('conversion_rules') }}
),

conversion_attributes as (
    select distinct attribute from conversion_rules
),

{%- set attributes_query -%}
        select distinct attribute from {{ var('conversion_rules') }}
{%- endset -%}

{%- if execute -%}
    {% set attributes = run_query(attributes_query).rows %}
{%- else -%}
    {% set attributes = [] %}
{%- endif -%}

raw_event_attributes as (
    select
        conversion_events.{{var('conversions_event_id_field')}} as conversion_event_id,
        conversion_events.{{var('conversions_timestamp_field')}} as conversion_timestamp,
        conversion_events.{{var('conversions_segmentation_id_field')}} as conversion_segmentation_id,
        conversion_attributes.attribute as attribute,
        case
        {% for attribute in attributes -%}
            when conversion_attributes.attribute = '{{ attribute[0] }}' then cast({{ attribute[0] }} as string)
        {% endfor %}
        end as value
    
    from
        conversion_events,  conversion_attributes
    
),

event_attributes as (
    select
        *
    from
        raw_event_attributes
    where
        value is not null
        
),

conversion_rules_bit as ( -- maps rule parts to their attribute types and adds a bit used for validating that all parts of any rule are matched
    select
        *,
        power(2, part - 1) as bit

    from
        conversion_rules
        
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
            when type = 'integer' then {{dbt.safe_cast("value", "integer")}}
            else null
        end as integer_value,
        case
            when type = 'float' then {{dbt.safe_cast("value", "numeric")}}
            else null
        end as float_value

    from
        conversion_rules_bit
),

rules_bitsums as ( --calculates the sum of the of the bits per rule needed to validate that all parts per rule are satisfied.

    select
        model_id,
        conversion_category,
        rule,
        power(2, max(part)) - 1 as bitsum

    from
        conversion_rules_bit

    group by
        model_id,
        conversion_category,
        rule

    order by
        model_id,
        conversion_category,
        rule
),

matched_parts as ( --returns all matched parts of the rules from the event stream (contains duplicates, handled downstreams.)

    select
        event_attributes.conversion_segmentation_id,
        event_attributes.conversion_event_id,
        event_attributes.conversion_timestamp,
        event_attributes.attribute,
        event_attributes.value,
        rules.model_id,
        rules.conversion_category,
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

matched_rules as ( -- returns fulfilled rules which indicates that an event matches a conversion category

    select
        matched_parts.conversion_segmentation_id,
        matched_parts.conversion_event_id,
        matched_parts.conversion_timestamp,
        matched_parts.model_id,
        matched_parts.conversion_category,
        matched_parts.rule,
        sum(matched_parts.bit) as bits,
        rules_bitsums.bitsum

    from
        matched_parts
        inner join rules_bitsums on
            rules_bitsums.model_id = matched_parts.model_id
            and rules_bitsums.conversion_category = matched_parts.conversion_category
            and rules_bitsums.rule = matched_parts.rule

    group by
        matched_parts.conversion_segmentation_id,
        matched_parts.conversion_event_id,
        matched_parts.conversion_timestamp,
        matched_parts.model_id,
        matched_parts.conversion_category,
        matched_parts.rule,
        rules_bitsums.bitsum

    having
        bits = rules_bitsums.bitsum
),

matched_categories as (-- Return one event record per conversion category (for the case where an event matches multiple rules within a conversion category)

    select distinct
        conversion_segmentation_id,
        conversion_event_id,
        conversion_timestamp,
        model_id,
        conversion_category

    from
        matched_rules
)

select * from matched_categories
