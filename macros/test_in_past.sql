{% test in_past(model, column_name) %}

    select *
    from {{ model }}
    where (cast({{ column_name }} as timestamp) >= convert_timezone('UTC', current_timestamp())::timestamp_ntz and  {{ column_name }} is not null)

{% endtest %}