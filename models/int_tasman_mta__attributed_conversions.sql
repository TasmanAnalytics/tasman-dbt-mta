with

conversion_events as (
    select * from {{ ref('int_tasman_mta__filtered_conversion_events') }}
),

attributed_touches as (
    select * from {{ ref('int_tasman_mta__attributed_touches') }}
),

joined_conversion_events as (

    select
        conversion_events.conversion_segmentation_id,
        conversion_events.conversion_event_id,
        conversion_events.conversion_timestamp,
        conversion_events.model_id,
        conversion_events.conversion_category,
        attributed_touches.touch_event_id,
        attributed_touches.touch_timestamp,
        attributed_touches.touch_category,
        attributed_touches.convert_touch_count,
        attributed_touches.convert_seq_up,
        attributed_touches.convert_seq_down,
        attributed_touches.interval_pre,
        attributed_touches.interval_post,
        attributed_touches.interval_convert,
        attributed_touches.spec,
        attributed_touches.conversion_share

    from
        conversion_events
    
    left join
        attributed_touches
        on conversion_events.conversion_event_id = attributed_touches.conversion_event_id
        and conversion_events.model_id = attributed_touches.model_id
)

select * from joined_conversion_events
