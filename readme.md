# Multi-Touch Attribution Engine

## What is Multi-Touch Attribution?

Multi-touch attribution is a method of marketing measurement that accounts for all the touchpoints on the customer journey and designates a certain amount of credit to each 
channel so that marketers can see the value that each touchpoint has on driving a conversion.

The core functionality of an attribution engine is its ability to match touches to conversions based on a series of rules, known as 'attribution models'.

Examples of attribution models include:
- Last touch - 100% conversion credit is applied to the touch point immediately before the conversion event
- First touch - 100% conversion credit is applied to the earliest occuring touch point
- U-shaped - 40% conversion credit is given to both first and last touches, with the remaining 20% split across all others

## Adding the dbt package

This package isn't currently publicly available and requires a token supplied by Tasman Analytics. It's best practice to use environment variables to store the token. You can do this locally by adding the following to your terminal configuration file (`.zprofile` or `.zsh` depending on your terminal)

```
export DBT_TASMAN_MTA_TOKEN="<token>"
```
For production runs, this will also need to be added to your production configuration. For dbt Cloud users, please follow [this guide](https://docs.getdbt.com/docs/build/environment-variables).

With the environment variable, you can use a git reference in the `packages.yml` file.

```
packages:
    - git: https://{{env_var('DBT_TASMAN_MTA_TOKEN')}}@github.com/TasmanAnalytics/tasman-dbt-mta.git
    revision: 0.1.1
```

## Configuring the Engine

The engine can be connected to your existing touch and conversion data sources using variables within the main project `dbt_project.yml` file

```
vars:
  tasman_dbt_mta:
    incremental: ""
    touches_model: "{{ ref() }}"
    touches_event_id_field: ""
    touches_timestamp_field: ""
    touches_segmentation_id_field: ""
    conversions_model: "{{ ref()}}"
    conversions_event_id_field: ""
    conversions_timestamp_field: ""
    conversions_segmentation_id_field: ""
    conversion_rules: "{{ ref() }}"
    touch_rules: "{{ ref() }}"
    attribution_rules: "{{ ref() }}"
    conversion_shares: "{{ ref() }}"
    attribution_windows: "{{ ref() }}"
    snowflake_prod_warehouse: ""
    snowflake_dev_warehouse: ""
```

`incremental`: "true" or "false" depending on whether the model should run using incremental models or not  
`touches_model`: Reference to the model containing touch data points  
`touches_timestamp_field`: Field within the `touches_model` that contains timestamps for each touch point  
`touches_event_id_field`: Field within the `touches_model` that contains a unique indentifier for each touch point  
`touches_segmentation_id_field`: Field within the `touches_model` that used to segment the touches. Typically this might be a user ID  
`conversions_model`: Reference to the model containing conversion data points  
`conversions_timestamp_field`: Field within the `conversions_model` that contains timestamps for each conversion  
`conversions_event_id_field`: Field within the `conversions_model` that contains a unique indentifier for each conversion  
`conversions_segmentation_id_field`: Field within the `conversions_model` that used to segment the conversions. Typically this might be a user ID  
`conversion_rules`: A seed file containing rules that can be used to filter specific conversions for each attribution model  
`touch_rules`: A seed file containing rules that can be used to filter specific touches for each attribution model  
`attribution_rules`: A seed file containing rules that are used to determine how touches are attributed to conversions (specs) for each attribution model  
`conversion_shares`: A seed file that maps to each attribution spec to determine the credit awarded to touches meeting each rule for each attribution model  
`attribution_windows`: A seed file that determines the maximum time between a touch and its conversion for each attribution model  
`snowflake_prod_warehouse`: This is the snowflake warehouse that should be used for when the target = 'prod'. An empty string will use the profile default warehouse. Not required for bigquery connections.  
`snowflake_dev_warehouse`: This is the snowflake warehouse that should be used for when the target = 'dev'. An empty string will use the profile default warehouse. Not required for bigquery connections.  


## Understanding the Configuration Seed Files

Consistent across all files is the `model_id` field, which described which attribution model the configuration relates to. This is a string field, and will appear alongside the attributed conversions in the output tables, and therefore, it is good to give each model a useful or relevant name that ensures uniqueness. For a last touch model, with a 30 day attribution window on a payment conversion, this might be `last_touch_30_days_payment`

### Touch and Conversion Rules

These files contains rules that are used to filter touches and conversions for specific attribution models. 
> N.B. There needs to be at least 1 rule per model for that model to receive any touches or conversions (otherwise they are all filtered out).

Touch Rules Example (line spaces are for readability - should not be included in the actual seed file):

```
model_id,touch_category,rule,part,attribute,type,relation,value

first_touch_lead_7_days,all_channels,1,1,touch_channel,string,<>,''

last_touch_purchase_30_days,all_channels,1,1,touch_channel,string,<>,''

u_shaped_purchase_all_time,all_channels,1,1,touch_channel,string,<>,''

w_shaped_30_days,all_channels,1,1,touch_channel,string,<>,''
```

Conversion Rules Example (line spaces are for readability - should not be included in the actual seed file):
```
model_id,conversion_category,rule,part,attribute,type,relation,value

first_touch_lead_7_days,purchase,1,1,conversion_type,string,=,purchase

last_touch_purchase_30_days,purchase,1,1,conversion_type,string,=,lead

u_shaped_purchase_all_time,purchase,1,1,conversion_type,string,=,purchase

w_shaped_30_days,lead,1,1,conversion_type,string,=,lead
w_shaped_30_days,purchase,1,1,conversion_type,string,=,purchase
```

`touch_category` / `conversion_category`: A text field that can be used to describe the category of touches or conversions for the model. This provides a mechanism to add additional attribution specific categorisations to the touches and conversions.  
`rule`: A 1-indexed integer defining the rule number for that touch category. Each rule is evaluated with OR logic, so if a category has 2 rules, the logic is rule 1 OR rule 2 has to be met for the touch to be assigned that category.  
`part`: A 1-indexed integer defining parts of a rule. Each rule part is considered with AND logic, so if a rule has 2 parts, the logic is part 1 AND part 2 has to be met for the touch to be evaluated **true** against that rule.  
`attribute`: The field within the `touches_model` or `conversions_model` that is being evaluated for the rule part. If the attribute doesn't match any fields in the model then logically is will always output **false**.  
`type`: The data type of the attribute field within the `touches_model` or `conversions_model`. This is important to enable correct casting of the value evaluated against the attribute.  
`relation`: The SQL boolean logic operator used to evalute the attribute and value. \
`value`: The value evaluted for the rule part. Empty strings can be a value but required empty quotes as in the example above.

### Attribution Rules

The attribution rules seed defines how touches are attributed to conversions for each attribution model. Each set of rules is grouped into a **spec**, and each spec can be assigned a different conversion share value in the conversion shares seed.

Attribution Rules Examples (line spaces are for readability - should not be included in the actual seed file):

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

`spec`: Short for specification, each spec defines each rule set of a particular attribution model, and be assigned a conversion share value. In the example above, it can be seen that 'single touch' models such as first touch and last touch only have 1 spec, whereas more complex multi-touch models will have more than one spec.
> N.B. where a spec returns true on more than one touch, the conversion share is split equally between the touches.

`rule`: A 1-indexed integer defining the rule number for that spec. Each rule is evaluated with OR logic, so if a category has 2 rules, the logic is rule 1 OR rule 2 has to be met for the touch to be assigned that category.  
`part`: A 1-indexed integer defining parts of a rule. Each rule part is considered with AND logic, so if a rule has 2 parts, the logic is part 1 AND part 2 has to be met for the touch to be evaluated **true** against that rule.  
`attribute`: The derived property that is being evaluated for the rule part. If the attribute doesn't match any fields in the model then logically is will always output **false**.  Properties available are: 
- `touch_category`: The category of the touch as per the touch rules
- `conversion_category`: The category of the conversion as per the conversion rules
- `convert_touch_count`: The total number of attributed touches.
- `convert_seq_up`: The consecutive touch number based on the timestamp ascending.
- `convert_seq_down`: The consecutive touch number based on the timestamp descending.
- `interval_pre`: Time in seconds between the touch and the touch preceding.
- `interval_post`: Time in seconds between the touch and the touch following.
- `interval_convert`: Time in seconds between the touch and the attributed conversion.

>The 'convert_seq' properties are used when the attribution rules are touch order based - should as first touch, last touch, u-shaped, w-shaped models.  
>The 'interval' preoprties are used when the attribution rules are time based - such as time decay model (less common)

`relation`: The SQL boolean logic operator used to evalute the attribute and value. \
`value`: The value evaluted for the rule part.

### Conversion Shares

The conversion shares seed is used to map attribution rules specs to decimal percentage conversion credits that are applied to matching touches.

Conversion Share Example (mapping to the attribution rule example above, using generally accepted conversion share values):
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

`spec`: The spec within the attribution rules seed that the share is to be applied to.  
`share`: The decimal percentage share that is granted to touches matching that spec. This share is split equally between all matching touches.

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

### Attribution Windows

The attribution window seed is used to define the maximum time between a touch and conversion for each attribution model.

Attribution window example:
```
model_id,att_window,time_seconds

first_touch_lead_7_days,7 day,604800

last_touch_purchase_30_days,30 day,2629746

u_shaped_purchase_all_time,all time,0

w_shaped_30_days,30 day,2629746
```

`att_window`: A string field used to describe the attribution window as plain text. This is passed as metadata in the output table as additional context.  
`time_seconds`: The maximum time in seconds allowed between a touch and conversion.


## Engine Outputs

The engine has two primary output models, attributed touches and attributed conversions.   
- **Attributed Touches** contains all filtered touches (based on the touch rules) across all attribution models that have been attributed to a conversion. Where touches have been attributed, there will be a `conversion_event_id` for that `touch_event_id`, as well as a conversion share value if appropriate.
- **Attributed Conversions** is this inverse of the attributed touches and contains all filtered conversions (based on the conversion rules) across all attribution models, whether or not they have attributed to a touch. Each `conversion_event_id` may appear once all multiple times depending on the number of attributed touches. Where `touch_event_id` is null, this indicates that the conversion is unattributed.


## Performance Tracking

Its unlikely that optimal attribution results will be achieved during the initial implementation of this engine - this is because the quality of the outputs are entirely dependent on the quality of the inputs along with tuning of the configurations. As such, an `attribution_performance_history` model has been added that will keep track of each time the attribution engine is run, and collect useful statistics that can help accelerate the implementation as well as monitor key metrics such as attribution rate.

## Current Limitations of the Engine
1. Handling conversion shares where the total number of touches is lower than the number of specs. For example, if there are only 2 touches but 3 attribution rule specs, then the total conversion shares will not sum to 100%. This needs to be accounted for when analysing the outputs.
2. Conversion shares are assigned at the touch level, not the session level. This means that the inputs into the engine need to account for this. It is therefore most often the case that internal touches should be filtered.