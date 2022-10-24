{% macro generate_uuid() -%}
  {{ return(adapter.dispatch('generate_uuid', 'tasman_dbt_mta')()) }}
{%- endmacro %}

{% macro snowflake__generate_uuid() %}
    uuid_string()
{% endmacro %}

{% macro bigquery__generate_uuid() %}
    generate_uuid()
{% endmacro %}