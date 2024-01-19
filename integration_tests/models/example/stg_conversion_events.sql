select
    {{ dbt.safe_cast("event", "string") }} as conversion_event_id,
    timestamp::timestamp as conversion_timestamp,
    {{ dbt.safe_cast("user", "string") }} as user_id,
    {{ dbt.safe_cast("type", "string") }} as conversion_type
from
    {{ ref('conversion_events') }}
