# MTA Configuration Guide

**Table of Contents**
- [Overview](#overview)
- [Configuring the Engine](#configuring-the-engine)
  - [Generic Configuration Template](#generic-configuration-template)
  - [Current Implementation](#current-implementation)
- [Configuring the Models](#configuring-the-models)
  - [Configuration Templates](#configuration-templates)
  - [Touch Rules](#touch-rules)
  - [Conversion Rules](#conversion-rules)
  - [Attribution Rules](#attribution-rules)
  - [Conversion Shares](#conversion-shares)
  - [Attribution Windows](#attribution-windows)
  - [Channel Mappings](#channel-mappings)
- [How to Modify Attribution Behavior](#how-to-modify-attribution-behavior)
  - [Scenario 1: Change Attribution Model](#scenario-1-change-attribution-model-eg-last-touch--first-touch)
  - [Scenario 2: Add a New Attribution Window](#scenario-2-add-a-new-attribution-window-eg-30-days)
  - [Scenario 3: Exclude Certain Channels](#scenario-3-exclude-certain-channels-from-attribution)
  - [Scenario 4: Create a Multi-Touch Model](#scenario-4-create-a-multi-touch-attribution-model-linear)
  - [Scenario 5: Add a New Enquiry Event Type](#scenario-5-add-a-new-enquiry-event-type)
- [Touches vs Sessions](#touches-vs-sessions)

---

# Overview

This guide documents the configuration of the Tasman MTA (Multi-Touch Attribution) engine. The MTA engine attributes conversions (purchases and enquiries) to marketing touches based on configurable rules.

**Package**: [TasmanAnalytics/tasman_dbt_mta](https://github.com/TasmanAnalytics/tasman_dbt_mta)

All attribution behavior is controlled via:
1. **dbt variables** in `dbt_project.yml` (engine configuration)
2. **CSV seed files** in `transformation/data/attribution/` (attribution rules)

---

# Configuring the Engine

The engine can be connected to your existing touch and conversion data sources using variables within the main project `dbt_project.yml` file.

## Generic Configuration Template

```yaml
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

**Variable Definitions:**

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

Consistent across all files is the `model_id` field, which describes which attribution model the configuration relates to. This is a string field, and will appear alongside the attributed conversions in the output tables, and therefore, it is good to give each model a useful or relevant name that ensures uniqueness. For a last touch model, with a 30 day attribution window on a payment conversion, this might be `last_touch_30_days_payment`

**Location**: `transformation/data/attribution/`

All attribution behavior is controlled via CSV seed files. These define the rules, windows, and models used by the MTA engine.

## Configuration Templates

Templated seed files (csvs) containing the required schema are included in the [`config_templates`](../config_templates/) folder. These must be copied to the appropriate data or seeds folder within the top-level dbt project.

---

## Touch Rules

**Purpose**: Defines which touch events are eligible for attribution

**File**: `transformation/data/attribution/touch_rules.csv`

These files contains rules that are used to filter touches for specific attribution models. 
> N.B. There needs to be at least 1 rule per model for that model to receive any touches (otherwise they are all filtered out).

### Schema

- **`model_id`** - Attribution model identifier
- **`touch_category`** - Category name for this touch type. A text field that can be used to describe the category of touches for the model. This provides a mechanism to add additional attribution specific categorisations to the touches.
- **`rule`** - Rule number (multiple rules can exist per model). Each rule is evaluated with OR logic, so if a category has 2 rules, the logic is rule 1 OR rule 2 has to be met for the touch to be assigned that category.
- **`part`** - Part number within a rule (for AND conditions). Each rule part is considered with AND logic, so if a rule has 2 parts, the logic is part 1 AND part 2 has to be met for the touch to be evaluated **true** against that rule.
- **`attribute`** - Field to evaluate (e.g., 'touch_channel'). The field within the `touches_model` that is being evaluated for the rule part. If the attribute doesn't match any fields in the model then no rows will be matched.
- **`type`** - Data type ('string', 'number', etc.). This is important to enable correct casting of the value evaluated against the attribute.
- **`relation`** - Comparison operator ('=', '<>', 'IN', etc.). The SQL boolean logic operator used to evalute the attribute and value.
- **`value`** - Value to compare against. Empty strings can be a value but required empty quotes as in the example below.

### Current Configuration

```csv
model_id,touch_category,rule,part,attribute,type,relation,value
last_session_touch_onsite_purchase,all_channels,1,1,touch_channel,string,<>,''
last_session_touch_onsite_purchase,all_channels,1,2,touch_channel,string,<>,Internal
last_session_touch_onsite_purchase,all_channels,1,3,touch_channel,string,<>,Direct
```

**Interpretation**: For the 'last_session_touch_onsite_purchase' model, include touches where:
- `touch_channel != ''` AND
- `touch_channel != 'Internal'` AND
- `touch_channel != 'Direct'`

This excludes direct traffic and internal navigation from attribution.

### Generic Examples

> N.B. line spaces are for readability - they should not be included in the actual seed file

```csv
model_id,touch_category,rule,part,attribute,type,relation,value

first_touch_lead_7_days,all_channels,1,1,touch_channel,string,<>,''

last_touch_purchase_30_days,all_channels,1,1,touch_channel,string,<>,''

u_shaped_purchase_all_time,all_channels,1,1,touch_channel,string,<>,''

w_shaped_30_days,all_channels,1,1,touch_channel,string,<>,''
```

---

## Conversion Rules

**Purpose**: Defines which conversion events are eligible for attribution

**File**: `transformation/data/attribution/conversion_rules.csv`

These files contains rules that are used to filter conversions for specific attribution models. 
> N.B. There needs to be at least 1 rule per model for that model to receive any conversions (otherwise they are all filtered out).

### Schema

- **`model_id`** - Attribution model identifier
- **`conversion_category`** - Category name ('purchase' or 'enquiry'). A text field that can be used to describe the category of conversions for the model. This provides a mechanism to add additional attribution specific categorisations to the conversions.
- **`rule`** - Rule number. Each rule is evaluated with OR logic.
- **`part`** - Part number within a rule. Each rule part is considered with AND logic.
- **`attribute`** - Field to evaluate (e.g., 'conversion_type'). The field within the `conversions_model` that is being evaluated for the rule part.
- **`type`** - Data type
- **`relation`** - Comparison operator
- **`value`** - Value to compare against

### Current Configuration

```csv
model_id,conversion_category,rule,part,attribute,type,relation,value
last_session_touch_onsite_purchase,purchase,1,1,conversion_type,string,=,purchase
last_session_touch_onsite_purchase,enquiry,1,1,conversion_type,string,=,enquiry
```

**Interpretation**: The model tracks both purchase and enquiry conversions.

### Generic Examples

> N.B. line spaces are for readability - they should not be included in the actual seed file

```csv
model_id,conversion_category,rule,part,attribute,type,relation,value

first_touch_lead_7_days,purchase,1,1,conversion_type,string,=,purchase

last_touch_purchase_30_days,purchase,1,1,conversion_type,string,=,lead

u_shaped_purchase_all_time,purchase,1,1,conversion_type,string,=,purchase

w_shaped_30_days,lead,1,1,conversion_type,string,=,lead
w_shaped_30_days,purchase,1,1,conversion_type,string,=,purchase
```

---

## Attribution Rules

**Purpose**: Defines which touches receive credit (e.g., last-touch, first-touch, linear)

**File**: `transformation/data/attribution/attribution_rules.csv`

The attribution rules seed defines how touches are attributed to conversions for each attribution model. Each set of rules is grouped into a **spec**, and each spec can be assigned a different conversion share value in the conversion shares seed.

### Schema

- **`model_id`** - Attribution model identifier
- **`spec`** - Specification number (allows multiple attribution specs per model). Short for specification, each spec defines the rule set of a particular attribution model, and can be assigned a conversion share value. In the example above, it can be seen that 'single touch' models such as first touch and last touch only have 1 spec, whereas more complex multi-touch or multi-conversion models will have more than one spec.
  > N.B. where a spec matches more than one touch, the conversion share is split equally between the touches.
- **`rule`** - Rule number. Each rule is evaluated with OR logic.
- **`part`** - Part number within a rule. Each rule part is considered with AND logic.
- **`attribute`** - Field to evaluate (e.g., 'convert_seq_down'). The derived property that is being evaluated for the rule part. If the attribute doesn't match any fields in the model then logically it will always output **false**. Properties available are:
  - `touch_category`: The category of the touch as per the touch rules
  - `conversion_category`: The category of the conversion as per the conversion rules
  - `convert_touch_count`: The total number of attributed touches.
  - `convert_seq_up`: The consecutive touch number based on the timestamp ascending.
  - `convert_seq_down`: The consecutive touch number based on the timestamp descending.
  - `interval_pre`: Time in seconds between the touch and the touch preceding.
  - `interval_post`: Time in seconds between the touch and the touch following.
  - `interval_convert`: Time in seconds between the touch and the attributed conversion.
  
  > The 'convert_seq' properties are used when the attribution rules are positional - such as first touch, last touch, u-shaped, w-shaped models.
  > The 'interval' properties are used when the attribution rules are time-based - such as a decay model.

- **`relation`** - Comparison operator. The SQL boolean logic operator used to evalute the attribute and value.
- **`value`** - Value to compare against

### Current Configuration

```csv
model_id,spec,rule,part,attribute,relation,value
last_session_touch_onsite_purchase,1,1,1,convert_seq_down,=,1
```

**Interpretation**: Only credit the last touch before conversion (`convert_seq_down = 1`).

**Common Attribution Patterns**:
- **Last Touch**: `convert_seq_down = 1`
- **First Touch**: `convert_seq_up = 1`
- **Linear**: No filter (all touches get equal credit)
- **Position-Based**: Multiple specs with different rules for first, last, and middle touches

### Generic Examples

> N.B. line spaces are for readability - they should not be included in the actual seed file

```csv
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

---

## Conversion Shares

**Purpose**: Defines how credit is split between touches (for multi-touch models)

**File**: `transformation/data/attribution/conversion_shares.csv`

The conversion shares seed is used to map attribution rules specs to decimal percentage conversion credits that are applied to matching touches.

### Schema

- **`model_id`** - Attribution model identifier
- **`spec`** - Specification number (matches `attribution_rules.csv`). The spec within the attribution rules seed that the share is to be applied to.
- **`share`** - Percentage of credit (decimal, 1.0 = 100%). The decimal percentage share that is granted to touches matching that spec. This share is split equally between all matching touches.

### Current Configuration

```csv
model_id,spec,share
last_session_touch_onsite_purchase,1,1
last_session_touch_onsite_purchase,2,1
```

**Interpretation**: Each spec gets 100% credit (last-touch model).

### Generic Examples

> N.B. line spaces are for readability - they should not be included in the actual seed file

```csv
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

**Multi-Touch Example** (Position-Based 40/20/40):
```csv
model_id,spec,share
position_based,1,0.4  # First touch
position_based,2,0.2  # Middle touches (split equally)
position_based,3,0.4  # Last touch
```

> **Example U-Shaped model**  
> 6 touches happen before conversion, the shares are split as follows:
> - Spec 1: First touch (Touch 1) = 40% share
> - Spec 2: Last Touch (Touch 6) = a 40% share 
> - Spec 3: All other touches (Touches 2,3,4,5) split a 20% share = 5% each

> **Example W-Shaped model**  
> 3 touches happen before lead conversion, 4 touches happen inbetween lead conversion and purchase conversion. The shares are split as follows:
> - Spec 1: First touch (Touch 1) = 30% share
> - Spec 2: Last touch before lead (Touch 3) = 30%
> - Spec 3: Last touch before purchase (Touch 7) = 30%
> - Spec 4: All other touches (Touches 2,4,5,6) split a 10% share = 2.5% each

---

## Attribution Windows

**Purpose**: Defines the lookback period for attributing touches to conversions

**File**: `transformation/data/attribution/attribution_windows.csv`

The attribution window seed is used to define the maximum time between a touch and conversion for each attribution model.

### Schema

- **`model_id`** - Attribution model identifier
- **`att_window`** - Window identifier. A string field used to describe the attribution window as plain text. This is passed as metadata in the output table as additional context.
- **`time_seconds`** - Lookback period in seconds. The maximum time in seconds allowed between a touch and conversion.

### Current Configuration

```csv
model_id,att_window,time_seconds
last_session_touch_onsite_purchase,last_7_days,604800
```

**Interpretation**: Only touches within 7 days (604,800 seconds) before conversion are eligible for attribution.

**Common Windows**:
- 1 day: 86,400
- 7 days: 604,800
- 30 days: 2,592,000
- 90 days: 7,776,000

### Generic Examples

> N.B. line spaces are for readability - they should not be included in the actual seed file

```csv
model_id,att_window,time_seconds

first_touch_lead_7_days,7 day,604800

last_touch_purchase_30_days,30 day,2629746

u_shaped_purchase_all_time,all time,0

w_shaped_30_days,30 day,2629746
```



# How to Modify Attribution Behavior

## Scenario 1: Change Attribution Model (e.g., Last-Touch → First-Touch)

**File to Edit**: `transformation/data/attribution/attribution_rules.csv`

**Current (Last-Touch)**:
```csv
model_id,spec,rule,part,attribute,relation,value
last_session_touch_onsite_purchase,1,1,1,convert_seq_down,=,1
```

**Change to First-Touch**:
```csv
model_id,spec,rule,part,attribute,relation,value
last_session_touch_onsite_purchase,1,1,1,convert_seq_up,=,1
```


---

## Scenario 2: Add a New Attribution Window (e.g., 30 days)

**File to Edit**: `transformation/data/attribution/attribution_windows.csv`

**Add Row**:
```csv
model_id,att_window,time_seconds
last_session_touch_onsite_purchase,last_30_days,2592000
```

**Note**: This will create additional rows in the output (one per window). You may need to update downstream models to filter to a specific window.

---

## Scenario 3: Exclude Certain Channels from Attribution

**File to Edit**: `transformation/data/attribution/touch_rules.csv`

**Example - Exclude 'Paid Social'**:
```csv
model_id,touch_category,rule,part,attribute,type,relation,value
last_session_touch_onsite_purchase,all_channels,1,1,touch_channel,string,<>,''
last_session_touch_onsite_purchase,all_channels,1,2,touch_channel,string,<>,Internal
last_session_touch_onsite_purchase,all_channels,1,3,touch_channel,string,<>,Direct
last_session_touch_onsite_purchase,all_channels,1,4,touch_channel,string,<>,Paid Social
```

**Steps**:
1. Edit `touch_rules.csv`
2. Run `dbt seed --select touch_rules`
3. Run `dbt run --select tasman_mta__attributed_conversions+`

---

## Scenario 4: Create a Multi-Touch Attribution Model (Linear)

**Files to Edit**: `attribution_rules.csv` and `conversion_shares.csv`

**attribution_rules.csv** (no filter = all touches):
```csv
model_id,spec,rule,part,attribute,relation,value
linear_model,1,1,1,convert_seq_down,>=,1
```

**conversion_shares.csv** (equal credit):
```csv
model_id,spec,share
linear_model,1,1
```

**Steps**:
1. Add new model_id to both files
2. Update `touch_rules.csv` and `conversion_rules.csv` with same model_id
3. Run `dbt seed --select attribution_rules conversion_shares touch_rules conversion_rules`
4. Run `dbt run --select tasman_mta__attributed_conversions+`

**Note**: For true linear attribution, the MTA engine will automatically split credit equally across all touches. The `share = 1` means each touch gets 100% of its allocated portion.

---



# Touches vs Sessions

The term used throughout this package to describe the actions taken by a given user is a touch. However, many organisations prefer to think about attribution from a session perspective. The engine supports both and isn't opinionated in its approach.

If working with individual touches, its important to filter out touches that come from an internal referrer - particularly when using a last-touch model - otherwise the last touch will almost always be an internal touch and provide little insight. 

If working with sessions, its important that sessionisation is completed upstream of the engine, and that the model contains 1 row per session.
