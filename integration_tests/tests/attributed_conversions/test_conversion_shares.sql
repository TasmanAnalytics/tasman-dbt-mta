select
    conversion_segmentation_id,
    model_id,
    sum(conversion_share) as total_conversion_share
from
    {{ ref('int_tasman_mta__attributed_conversions') }}

group by
    conversion_segmentation_id,
    model_id

having
    total_conversion_share > 1
