{% macro get_where_subquery(relation) -%}
    {% set where = config.get('where') %}
    {% if where %}
        {% if '__test_hours_ago__' in where %}
            {% set hours = var('test_hours') %}
            {% set n_hours_ago = dbt.dateadd('hour', -hours, dbt.current_timestamp()) %}
            {% set where = where | replace('__test_hours_ago__', n_hours_ago) %}
        {% endif %}
        {%- set filtered -%}
            (select * from {{ relation }} where {{ where }}) dbt_subquery
        {%- endset -%}
        {% do return(filtered) %}
    {%- else -%}
        {% do return(relation) %}
    {%- endif -%}
{%- endmacro %}
