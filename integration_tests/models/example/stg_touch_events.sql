select
    {{ dbt.safe_cast("event", "string") }} as touch_event_id,
    event_timestamp as touch_timestamp,
    {{ dbt.safe_cast("user", "string") }} as user_id,
    {{ dbt.safe_cast("channel", "string") }} as touch_channel
from
    {{ ref('touch_events') }}
