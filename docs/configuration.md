- [Configuring the Engine](#configuring-the-engine)
- [Configuring the Models](#configuring-the-models)
  - [Configuration Templates](#configuration-templates)
  - [Touch and Conversion Rules](#touch-and-conversion-rules)
    - [Touch Rules Example](#touch-rules-example)
    - [Conversion Rules Example](#conversion-rules-example)
  - [Attribution Rules](#attribution-rules)
    - [Attribution Rules Example](#attribution-rules-example)
  - [Conversion Shares](#conversion-shares)
    - [Conversion Share Example](#conversion-share-example)
  - [Attribution Windows](#attribution-windows)
    - [Attribution Window Example](#attribution-window-example)
- [Touches vs Sessions](#touches-vs-sessions)


# Configuring the Engine

The engine can be connected to your existing touch and conversion data sources using variables within the main project `dbt_project.yml` file

```
vars:
  tasman_dbt_mta:
    incremental: ""
    touches_model: "{{ ref() }}"
    touches_event_id_field: ""
    touches_timestamp_field: ""
    touches_user_id_field: ""
    conversions_model: "{{ ref()}}"
    conversions_event_id_field: ""
    conversions_timestamp_field: ""
    conversions_user_id_field: ""
    conversion_rules: "{{ ref() }}"
    touch_rules: "{{ ref() }}"
    attribution_rules: "{{ ref() }}"
    conversion_shares: "{{ ref() }}"
    attribution_windows: "{{ ref() }}"
    snowflake_prod_warehouse: ""
    snowflake_dev_warehouse: ""
```

- **`incremental`:** "true" or "false" depending on whether the model should run using incremental models or not  
- **`touches_model`:** Reference to the model containing touch data points. This can be touches or sessions - [read more here](#touches-vs-sessions).  
- **`touches_timestamp_field`:** Field within the `touches_model` that contains timestamps for each touch point. 
  - Touches must occur in the past, and there are column tests throughout the package to validate this.  
- **`touches_event_id_field`:** Field within the `touches_model` that contains a unique indentifier for each touch point  
- **`touches_user_id_field`:** Field within the `touches_model` that contains the user identifier
- **`conversions_model`:** Reference to the model containing conversion data points  
- **`conversions_timestamp_field`:** Field within the `conversions_model` that contains timestamps for each conversion.
  - Conversions must occur in the past, and there are column tests throughout the package to validate this.  
- **`conversions_event_id_field`:** Field within the `conversions_model` that contains a unique indentifier for each conversion  
- **`conversions_user_id_field`:** Field within the `conversions_model` that contains the user identifier 
- **`conversion_rules`:** A seed file containing rules that can be used to filter specific conversions for each attribution model  
- **`touch_rules`:** A seed file containing rules that can be used to filter specific touches for each attribution model  
- **`attribution_rules`:** A seed file containing rules that are used to determine how touches are attributed to conversions (specs) for each attribution model  
- **`conversion_shares`:** A seed file that maps to each attribution spec to determine the credit awarded to touches meeting each rule for each attribution model  
- **`attribution_windows`:** A seed file that determines the maximum time between a touch and its conversion for each attribution model  
- **`snowflake_prod_warehouse`:** **(Snowflake connections only)** This is the snowflake warehouse that should be used for when the target = 'prod'. An empty string will use the profile default warehouse.
- **`snowflake_dev_warehouse`:** **(Snowflake connections only)** This is the snowflake warehouse that should be used for when the target = 'dev'. An empty string will use the profile default warehouse.


# Configuring the Models

Consistent across all files is the `model_id` field, which described which attribution model the configuration relates to. This is a string field, and will appear alongside the attributed conversions in the output tables, and therefore, it is good to give each model a useful or relevant name that ensures uniqueness. For a last touch model, with a 30 day attribution window on a payment conversion, this might be `last_touch_30_days_payment`

## Configuration Templates
Templated seed files (csvs) containing the required schema are included in the [`config_templates`](../config_templates/) folder. These must be copied to the appropriate data or seeds folder within the top-level dbt project.

## Touch and Conversion Rules

These files contains rules that are used to filter touches and conversions for specific attribution models. 
> N.B. There needs to be at least 1 rule per model for that model to receive any touches or conversions (otherwise they are all filtered out).

### Touch Rules Example
> N.B. line spaces are for readability - they should not be included in the actual seed file

```
model_id,touch_category,rule,part,attribute,type,relation,value

first_touch_lead_7_days,all_channels,1,1,touch_channel,string,<>,''

last_touch_purchase_30_days,all_channels,1,1,touch_channel,string,<>,''

u_shaped_purchase_all_time,all_channels,1,1,touch_channel,string,<>,''

w_shaped_30_days,all_channels,1,1,touch_channel,string,<>,''
```

### Conversion Rules Example 
> N.B. line spaces are for readability - they should not be included in the actual seed file
```
model_id,conversion_category,rule,part,attribute,type,relation,value

first_touch_lead_7_days,purchase,1,1,conversion_type,string,=,purchase

last_touch_purchase_30_days,purchase,1,1,conversion_type,string,=,lead

u_shaped_purchase_all_time,purchase,1,1,conversion_type,string,=,purchase

w_shaped_30_days,lead,1,1,conversion_type,string,=,lead
w_shaped_30_days,purchase,1,1,conversion_type,string,=,purchase
```

**Schema:**
- **`model_id`:** The identifier for the attribution model that the rule corresponds to.
- **`touch_category` / `conversion_category`:** A text field that can be used to describe the category of touches or conversions for the model. This provides a mechanism to add additional attribution specific categorisations to the touches and conversions.  
- **`rule`:** A 1-indexed integer defining the rule number for that touch category. Each rule is evaluated with OR logic, so if a category has 2 rules, the logic is rule 1 OR rule 2 has to be met for the touch to be assigned that category.  
- **`part`:** A 1-indexed integer defining parts of a rule. Each rule part is considered with AND logic, so if a rule has 2 parts, the logic is part 1 AND part 2 has to be met for the touch to be evaluated **true** against that rule.  
- **`attribute`:** The field within the `touches_model` or `conversions_model` that is being evaluated for the rule part. If the attribute doesn't match any fields in the model then no rows will be matched.  
- **`type`:** The data type of the attribute field within the `touches_model` or `conversions_model`. This is important to enable correct casting of the value evaluated against the attribute.  
- **`relation`:** The SQL boolean logic operator used to evalute the attribute and value.  
- **`value`:** The value evaluted for the rule part. Empty strings can be a value but required empty quotes as in the example above.

## Attribution Rules

The attribution rules seed defines how touches are attributed to conversions for each attribution model. Each set of rules is grouped into a **spec**, and each spec can be assigned a different conversion share value in the conversion shares seed.

### Attribution Rules Example
> N.B. line spaces are for readability - they should not be included in the actual seed file

```
model_id,spec,rule,part,attribute,relation,value

first_touch_lead_7_days,1,1,1,convert_seq_up,=,1

last_touch_purchase_30_days,1,1,1,convert_seq_down,=,1

u_shaped_purchase_all_time,1,1,1,convert_seq_up,=,1
u_shaped_purchase_all_time,2,1,1,convert_seq_down,=,1
u_shaped_purchase_all_time,3,1,1,convert_seq_up,>,1
u_shaped_purchase_all_time,3,1,2,convert_seq_down,<,1

w_shaped_30_days,1,1,1,convert_seq_up,=,1
w_shaped_30_days,1,1,2,conversion_category,=,lead
w_shaped_30_days,2,1,1,convert_seq_down,=,1
w_shaped_30_days,2,1,2,conversion_category,=,lead
w_shaped_30_days,3,1,1,convert_seq_down,=,1
w_shaped_30_days,3,1,2,conversion_category,=,purchase
w_shaped_30_days,4,1,1,convert_seq_up,>,1
w_shaped_30_days,4,1,2,convert_seq_down,>,1
w_shaped_30_days,4,1,3,conversion_category,=,lead
w_shaped_30_days,4,2,1,convert_seq_down,>,1
w_shaped_30_days,4,2,2,conversion_category,=,purchase

```
**Schema:**
- **`model_id`:** The identifier for the attribution model that the rule corresponds to.
- **`spec`:** Short for specification, each spec defines the rule set of a particular attribution model, and can be assigned a conversion share value. In the example above, it can be seen that 'single touch' models such as first touch and last touch only have 1 spec, whereas more complex multi-touch or multi-conversion models will have more than one spec.
> N.B. where a spec matches than one touch, the conversion share is split equally between the touches.

- **`rule`:** A 1-indexed integer defining the rule number for that spec. Each rule is evaluated with OR logic, so if a category has 2 rules, the logic is rule 1 OR rule 2 has to be met for the touch to be assigned that category.
- **`part`:** A 1-indexed integer defining parts of a rule. Each rule part is considered with AND logic, so if a rule has 2 parts, the logic is part 1 AND part 2 has to be met for the touch to be evaluated **true** against that rule.
- **`attribute`**: The derived property that is being evaluated for the rule part. If the attribute doesn't match any fields in the model then logically is will always output **false**.  Properties available are: 
  - `touch_category`: The category of the touch as per the touch rules
  - `conversion_category`: The category of the conversion as per the conversion rules
  - `convert_touch_count`: The total number of attributed touches.
  - `convert_seq_up`: The consecutive touch number based on the timestamp ascending.
  - `convert_seq_down`: The consecutive touch number based on the timestamp descending.
  - `interval_pre`: Time in seconds between the touch and the touch preceding.
  - `interval_post`: Time in seconds between the touch and the touch following.
  - `interval_convert`: Time in seconds between the touch and the attributed conversion.

>The 'convert_seq' properties are used when the attribution rules are positional - such as first touch, last touch, u-shaped, w-shaped models.
>The 'interval' properties are used when the attribution rules are time-based - such as a decay model.

- **`relation`:** The SQL boolean logic operator used to evalute the attribute and value.
- **`value`:** The value evaluted for the rule part.

## Conversion Shares

The conversion shares seed is used to map attribution rules specs to decimal percentage conversion credits that are applied to matching touches.

### Conversion Share Example
> N.B. line spaces are for readability - they should not be included in the actual seed file
```
model_id,spec,share

first_touch_lead_7_days,1,1

last_touch_purchase_30_days,1,1

u_shaped_purchase_all_time,1,0.4
u_shaped_purchase_all_time,2,0.4
u_shaped_purchase_all_time,3,0.2

w_shaped_30_days,1,0.3
w_shaped_30_days,2,0.3
w_shaped_30_days,3,0.3
w_shaped_30_days,4,0.1
```
**Schema:**
- **`model_id`:** The identifier for the attribution model that the rule corresponds to.
- **`spec`:** The spec within the attribution rules seed that the share is to be applied to.  
- **`share`:** The decimal percentage share that is granted to touches matching that spec. This share is split equally between all matching touches.

> Example U-Shaped model  
> 6 touches happen before conversion, the shares are split as follows:
> - Spec 1: First touch (Touch 1) = 40% share
> - Spec 2: Last Touch (Touch 6) = a 40% share 
> - Spec 3: All  other touches (Touches 2,3,4,5) split a 20% share = 5% each

> Example W-Shaped model  
> 3 touches happen before lead conversion, 4 touches happen inbetween lead conversion and purchase conversion. The shares are split as follows:
> - Spec 1: First touch (Touch 1) = 30% share
> - Spec 2: Last touch before lead (Touch 3) = 30%
> - Spec 3: Last touch before purchase (Touch 7) = 30%
> - Spec 4: All other touches (Touches 2,4,5,6) split a 10% share = 2.5% each

## Attribution Windows

The attribution window seed is used to define the maximum time between a touch and conversion for each attribution model.

### Attribution Window Example
> N.B. line spaces are for readability - they should not be included in the actual seed file
```
model_id,att_window,time_seconds

first_touch_lead_7_days,7 day,604800

last_touch_purchase_30_days,30 day,2629746

u_shaped_purchase_all_time,all time,0

w_shaped_30_days,30 day,2629746
```
**Schema:**
- **`model_id`:** The identifier for the attribution model that the rule corresponds to.
- **`att_window`:** A string field used to describe the attribution window as plain text. This is passed as metadata in the output table as additional context.  
- **`time_seconds`:** The maximum time in seconds allowed between a touch and conversion.


# Touches vs Sessions
The term used throughout this package to describe the actions taken by a given user is a touch. However, many organisations prefer to think about attribution from a session perspective. The engine supports both and isn't opionated in its approach.

If working with individual touches, its important to filter out touches that come from an internal referrer - particularly when using a last-touch model - otherwise the last touch will almost always be an internal touch and provide little insight. 

If working with sessions, its important that sessionisation is completed upstream of the engine, and that the model contains 1 row per session.