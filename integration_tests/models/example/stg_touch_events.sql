select
    {{ dbt.safe_cast("event", "string") }} as touch_event_id,
    timestamp::timestamp as touch_timestamp,
    {{ dbt.safe_cast("segmentation", "string") }} as user_id,
    {{ dbt.safe_cast("channel", "string") }} as touch_channel
from
    {{ ref('touch_events') }}
