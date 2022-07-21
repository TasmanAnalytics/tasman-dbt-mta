{% test in_past(model, column_name) %}

    select *
    from {{ model }}
    where (cast({{ column_name }} as timestamp) >= current_timestamp() and  {{ column_name }} is not null)

{% endtest %}