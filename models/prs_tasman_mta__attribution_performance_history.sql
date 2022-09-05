{{
    config(
        materialized='incremental',
        schema='attribution',
        on_schema_change="sync_all_columns",
        full_refresh=false
    )
}}

with

    attribution_stats as (
        select
            uuid_string() as run_id,
            {{ current_utc_time() }} as run_date,
            (select count(distinct {{var('touches_event_id_field')}}) from {{ var('touches_model') }}) as input_touches,
            (select count(distinct touch_event_id) from {{ ref('int_tasman_mta__filtered_touch_events') }}) as filtered_touches,
            input_touches - filtered_touches as removed_touches,
            (select count(distinct touch_event_id) from {{ ref('int_tasman_mta__attributed_touches') }} where conversion_event_id is not null) as attributed_touches,
            filtered_touches - attributed_touches as unattributed_touches,
            (select count(distinct {{var('conversions_event_id_field')}}) from {{ var('conversions_model') }}) as input_conversions,
            (select count(distinct conversion_event_id) from {{ ref('int_tasman_mta__filtered_conversion_events') }}) as filtered_conversions,
            input_conversions - filtered_conversions as removed_conversions,
            (select count(distinct conversion_event_id) from {{ ref('int_tasman_mta__attributed_conversions') }} where touch_event_id is not null) as attributed_conversions,
            (select count(distinct conversion_event_id) from {{ ref('int_tasman_mta__attributed_conversions') }} where touch_event_id is null) as unattributed_conversions,
            attributed_conversions/filtered_conversions as attribution_rate
    )

    select * from attribution_stats