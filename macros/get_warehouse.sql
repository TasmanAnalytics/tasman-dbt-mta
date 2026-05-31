{% macro get_warehouse() %}
    {% if target.type != 'snowflake' %}
        {{ return('') }}
    {% elif target.name == 'prod' and var('snowflake_prod_warehouse') != '' %}
        {{ var('snowflake_prod_warehouse') }}
    {% elif target.name == 'dev' and var('snowflake_dev_warehouse') != '' %}
        {{ var('snowflake_dev_warehouse') }}
    {% else %}
        {{ target.warehouse }}
    {% endif %}
{% endmacro %}
