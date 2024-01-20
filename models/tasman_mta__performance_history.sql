{{
    config(
        materialized='incremental',
        on_schema_change="sync_all_columns",
        snowflake_warehouse=get_warehouse(),
        full_refresh=false
    )
}}

with

models as (
    select model_id from {{var('touch_rules')}}
    union all
    select model_id from {{var('conversion_rules')}}
    union all
    select model_id from {{var('conversion_shares')}}
    union all
    select model_id from {{var('attribution_rules')}}
    union all
    select model_id from {{var('attribution_windows')}}
),

distinct_models as (
    select distinct model_id from models
),

input_touches as (
    select
        count(distinct {{var('touches_event_id_field')}}) as input_touches
    from
        {{ var('touches_model') }}
),

input_touches_by_model as (
    select
        distinct_models.model_id,
        input_touches.input_touches
    
    from
        input_touches, distinct_models
),

filtered_touches_by_model as (
    select
        model_id,
        count(distinct touch_event_id) as filtered_touches
    from
        {{ ref('tasman_mta__filtered_touch_events') }}
    group by
        model_id
),

attributed_touches_by_model as (
    select
        model_id,
        count(distinct touch_event_id) as attributed_touches
    from
        {{ ref('tasman_mta__attributed_touches') }}
    where
        conversion_event_id is not null
    group by
        model_id
),

input_conversions as (
    select
        count(distinct {{var('conversions_event_id_field')}}) as input_conversions
    from
        {{ var('conversions_model') }}
),

input_conversions_by_model as (
    select
        distinct_models.model_id,
        input_conversions.input_conversions
    
    from
        input_conversions, distinct_models
),

filtered_conversions_by_model as (
    select
        model_id,
        count(distinct conversion_event_id) as filtered_conversions
    from
        {{ ref('tasman_mta__filtered_conversion_events') }}
    group by
        model_id
),

attributed_conversions_by_model as (
    select
        model_id,
        count(distinct conversion_event_id) as attributed_conversions
    from
        {{ ref('tasman_mta__attributed_conversions') }}
    where
        touch_event_id is not null
    group by
        model_id
),

unattributed_conversions_by_model as (
    select
    model_id,
        count(distinct conversion_event_id) as unattributed_conversions
    from
        {{ ref('tasman_mta__attributed_conversions') }}
    where
        touch_event_id is null
    group by
        model_id
),

conversion_share_by_model as (
    select
        model_id,
        sum(conversion_share) as total_conversion_share
    from
        {{ ref('tasman_mta__attributed_conversions') }}
    group by
        model_id  
),

run_details as (
    select
        {{ generate_uuid() }} as run_id,
        {{ current_utc_time() }} as run_date
),

run_details_by_model as (
    select
        run_details.run_id,
        run_details.run_date,
        distinct_models.model_id
    
    from
        run_details, distinct_models
),

joined_stats as (
    select
        run_details_by_model.run_id,
        run_details_by_model.run_date,
        run_details_by_model.model_id,
        input_touches_by_model.input_touches,
        filtered_touches_by_model.filtered_touches,
        attributed_touches_by_model.attributed_touches,
        input_conversions_by_model.input_conversions,
        filtered_conversions_by_model.filtered_conversions,
        attributed_conversions_by_model.attributed_conversions,
        unattributed_conversions_by_model.unattributed_conversions,
        conversion_share_by_model.total_conversion_share
    
    from
        run_details_by_model
    
    left join
        input_touches_by_model
        on run_details_by_model.model_id = input_touches_by_model.model_id
    
    left join
        filtered_touches_by_model
        on run_details_by_model.model_id = filtered_touches_by_model.model_id
    
    left join
        attributed_touches_by_model
        on run_details_by_model.model_id = attributed_touches_by_model.model_id
    
    left join
        input_conversions_by_model
        on run_details_by_model.model_id = input_conversions_by_model.model_id
    
    left join
        filtered_conversions_by_model
        on run_details_by_model.model_id = filtered_conversions_by_model.model_id
    
    left join
        attributed_conversions_by_model
        on run_details_by_model.model_id = attributed_conversions_by_model.model_id
    
    left join
        unattributed_conversions_by_model
        on run_details_by_model.model_id = unattributed_conversions_by_model.model_id
    
    left join
        conversion_share_by_model
        on run_details_by_model.model_id = conversion_share_by_model.model_id

),

calculated_stats as (
    select
        run_id,
        run_date,
        model_id,
        input_touches,
        filtered_touches,
        input_touches - filtered_touches as removed_touches,
        attributed_touches,
        filtered_touches - attributed_touches as unattributed_touches,
        input_conversions,
        filtered_conversions,
        input_conversions - filtered_conversions as removed_conversions,
        attributed_conversions,
        unattributed_conversions,
        attributed_conversions/filtered_conversions as attribution_rate,
        total_conversion_share
    
    from
        joined_stats
)

select * from calculated_stats