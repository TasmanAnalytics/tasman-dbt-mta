{% test greater_than_zero(model, column_name) %}

    select *
    from {{ model }}
    where ({{ column_name }} < 0 and {{ column_name }} is not null)

{% endtest %}