select
    conversion_user_id,
    model_id,
    sum(conversion_share) as total_conversion_share
from
    {{ ref('tasman_mta__attributed_conversions') }}

group by
    conversion_user_id,
    model_id

having
    total_conversion_share > 1
