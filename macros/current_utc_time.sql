{% macro current_utc_time() -%}
  {{ return(adapter.dispatch('current_utc_time', 'tasman_dbt_mta')()) }}
{%- endmacro %}

{% macro snowflake__current_utc_time() %}
    convert_timezone('UTC', current_timestamp)::timestamp_ntz
{% endmacro %}

{% macro bigquery__current_utc_time() %}
    current_timestamp()
{% endmacro %}