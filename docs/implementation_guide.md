# MTA Implementation Guide

This package calculates which marketing touchpoints deserve credit for driving conversions, enabling sophisticated marketing attribution analysis beyond simple last-click models.

**Table of Contents**
- [What the MTA Engine Does](#what-the-mta-engine-does)
- [Prerequisites](#prerequisites)
  - [Identity Resolution](#identity-resolution)
- [Architecture & Data Flow](#architecture--data-flow)
  - [Input Models](#input-models)
  - [MTA Engine Models](#mta-engine-models-from-package)
  - [Output Models](#output-models)
- [Troubleshooting](#troubleshooting)

---

## What the MTA Engine Does

The MTA engine:
1. Takes **touch events** (page views with marketing attribution data)
2. Takes **conversion events** (purchases and enquiries)
3. Applies **configurable attribution rules** to determine which touch events get credit
4. Outputs **attributed conversions** showing the relationship between touch events and conversions


---

## Prerequisites

### Identity Resolution

**The MTA engine needs stable user identifiers to link touch events across sessions.**

Therefore you should do identity stitching/resolution before `dmn_touch_events` and `dmn_conversion_events`. Without proper identity resolution, the engine cannot accurately attribute conversions to touch events that occurred in different sessions or devices.

---

## Architecture & Data Flow

### Input Models

#### 1. Touch Events Model
You will need a model which lists all your touch-events. Something like this: 

**Example**: `dmn_web_touch_events`  
**Purpose**: Contains marketing touch events eligible for attribution (e.g., page views, ad clicks). 1 row per touch event.  
**Configuration**: Set via `touches_model` variable in `dbt_project.yml` ([see Configuration Guide](configuration.md#configuring-the-engine))

> **Note:** The engine supports both individual touch events and session-level data. See [Touches vs Sessions](configuration.md#touches-vs-sessions) for guidance on which approach to use.

##### Attribution Data Priority

When dealing with event data, it's common to have multiple sources of attribution information for a single event. By the time the event reaches the touch events model, you need to have consolidated this down to four standardized columns:
- `touch_channel`
- `touch_source`
- `touch_medium`
- `touch_campaign`

**Priority Waterfall** (highest to lowest):

**1. Ad Platform Data** (highest priority)
   - **Source**: Direct from ad platforms via product links or click IDs (e.g., `gclid`)
   - **Use case**: Most accurate for paid campaigns
   - **Example**: Google Ads campaign data when GA4 is linked to Google Ads
   
**2. Cross-Channel Data**
   - **Source**: Analytics platform's auto-classification (entrance events only)
   - **Use case**: Good for organic and referral traffic
   - **Example**: GA4's automatic source/medium classification
   
**3. Event-Scope Parameters**
   - **Source**: URL parameters captured at the event level
   - **Use case**: Captures mid-session attribution changes
   - **Example**: UTM parameters on specific page views
   
**4. Session-Scope Parameters** (lowest priority)
   - **Source**: Session-level UTM parameters (entrance events only)
   - **Use case**: Fallback for manual campaign tracking
   - **Example**: UTMs from the landing page

**Example Priority Logic**:
```sql
case
    when google_ads_campaign_id is not null or gclid is not null 
        then google_ads_source  -- Priority 1: Ad platform data
    when is_entrance_event and cross_channel_source is not null 
        then cross_channel_source  -- Priority 2: Auto-classification
    when event_scope_source is not null 
        then event_scope_source  -- Priority 3: Event-level UTMs
    when is_entrance_event 
        then session_scope_source  -- Priority 4: Session-level UTMs
end as touch_source
```

---

##### What Counts as a Touch Event?

While technically you could include all page views as touches, the MTA engine will attribute conversions based on your touch rules. Think carefully about what events you include in the touch events model—one of these events may ultimately be selected as the signal that led to a conversion.

Common events to consider excluding:
- **Internal navigations** - Mid-session page views that don't indicate origin (these rarely provide attribution value)
- **Direct traffic at session start** - If a session starts with no attribution data, this isn't an informative touch
- **Low-value interactions** - Events that don't represent meaningful marketing engagement

You can handle these exclusions either:
1. By filtering them out of the touch events model itself, or
2. By configuring touch rules (in `touch_rules.csv`) to exclude them during attribution

Consider: Would you be comfortable seeing this event reported as the source of a conversion? If not, it probably shouldn't be in your touch events model.

**Typical Filtering Criteria**:
- Valid event type (e.g., `event_name = 'page_view'`)
- User identifier is not null
- Cookie consent obtained (if applicable)

**Required Fields** (configurable via variables):
- Event ID field (set via `touches_event_id_field`)
- Timestamp field (set via `touches_timestamp_field`)
- User ID field (set via `touches_user_id_field`)

**Common Additional Fields**:
- Session identifier
- Marketing attribution fields: `touch_channel`, `touch_source`, `touch_medium`, `touch_campaign`
- Ad platform identifiers: `gclid`, `campaign_id`, `ad_group_id`
- Context fields: `device_category`, `country`

**Typical Materialization**: Incremental (delete+insert) for performance

---

#### 2. Conversion Events Model
You will also need a model which lists all your conversion-events. Something like this: 

**Example**: `dmn_web_conversion_events`  
**Purpose**: Contains conversion events that you want to attribute to marketing touches. 1 row per conversion.
**Configuration**: Set via `conversions_model` variable in `dbt_project.yml` ([see Configuration Guide](configuration.md#configuring-the-engine))

**Typical Filtering Criteria**:
- Valid conversion event types
- User identifier is not null
- Resolved user identity available (if using identity resolution)
- Cookie consent obtained (if applicable)
- Business identifier field is not null (e.g., transaction ID, lead ID)

**Required Fields** (configurable via variables):
- Event ID field (set via `conversions_event_id_field`)
- Timestamp field (set via `conversions_timestamp_field`)
- User ID field (set via `conversions_user_id_field`)

**Common Additional Fields**:
- Session identifier
- Conversion type/category field
- Business identifiers (transaction IDs, reference numbers, etc.)
- Conversion value fields (revenue, quantity, etc.)

These two models form your input tables to the MTA package. 

---

### MTA Engine Models (from Package)

The Tasman MTA package generates several models. The primary output model is:

#### `tasman_mta__attributed_conversions`
**Generated by**: Tasman MTA package  
**Purpose**: Attribution results linking touches to conversions  
**Materialization**: Controlled by `incremental` var (currently set to `"false"` = full refresh)

**Key Output Fields**:
- `conversion_event_id` - Links to `dmn_web_conversion_events.event_id`
- `touch_event_id` - Links to `dmn_web_touch_events.event_id`
- `model_id` - Attribution model identifier (e.g., 'last_session_touch_onsite_purchase')
- `conversion_category` - 'purchase' or 'enquiry'
- `touch_category` - From touch_rules seed (e.g., 'all_channels')
- `att_window` - Attribution window identifier (e.g., 'last_7_days')
- `conversion_share` - Percentage of conversion credit (decimal, e.g., 1.0 = 100%)
- `convert_touch_count` - Total touches in journey
- `convert_seq_up` - Touch position from first (1 = first touch)
- `convert_seq_down` - Touch position from conversion (1 = last touch)
- `interval_pre` - Seconds between previous touch and this touch
- `interval_post` - Seconds between this touch and next touch
- `interval_convert` - Seconds between this touch and conversion

**Other Package Models**:
- `tasman_mta__filtered_touch_events` - Intermediate filtered touches
- `tasman_mta__filtered_conversion_events` - Intermediate filtered conversions
- `tasman_mta__performance_history` - Attribution performance metrics


---

### Output Models

You will need to define a model to pick up the output from the MTA engine (which is in `tasman_mta__attributed_conversions`) and enrich it with additional context from your touch events and conversion events.

#### Creating an Attributed Conversions Output Model

**Purpose**: Enriches MTA engine output with full event details and business context  
**Typical Materialization**: Table  
**Grain**: One row per conversion (deduplicated by business identifier)

**Example Model Structure**:

```sql
with conversion_events as (
    -- All conversion events (purchases, enquiries, etc.)
    select *
    from {{ ref('dmn_web_conversion_events') }}
),

conversion_attributions as (
    -- Attribution results from MTA engine
    -- Filter to touches with credit OR unattributed conversions
    select *
    from {{ ref("tasman_mta__attributed_conversions") }}
    where conversion_share > 0 or touch_event_id is null
),

touch_events as (
    -- Full touch event details for enrichment
    select * from {{ ref("dmn_web_touch_events") }}
),

sessions as (
    -- Session data for fallback when no touch is attributed
    select * from {{ ref("dmn_web_sessions") }}
),

final as (
    select
        -- Conversion event details
        conversion_events.event_timestamp as conversion_event_timestamp,
        conversion_events.event_name as conversion_event_name,
        conversion_events.event_id as conversion_event_id,
        conversion_events.session_id as conversion_session_id,
        conversion_events.user_id,
        conversion_events.user_pseudo_id,
        conversion_events.conversion_type,
        conversion_events.business_identifier,  -- e.g., booking_reference, enquiry_ref, transaction_id

        -- Attribution metrics from MTA engine
        conversion_attributions.model_id,
        conversion_attributions.conversion_category,
        conversion_attributions.touch_category,
        conversion_attributions.att_window,
        conversion_attributions.conversion_share,
        conversion_attributions.convert_touch_count,
        conversion_attributions.convert_seq_up,
        conversion_attributions.convert_seq_down,
        conversion_attributions.interval_pre,
        conversion_attributions.interval_post,
        conversion_attributions.interval_convert,

        -- Last touch details (enriched from touch events)
        coalesce(touch_events.event_timestamp, sessions.session_start_at) as last_touch_timestamp,
        touch_events.event_name as last_touch_event_name,
        touch_events.event_id as last_touch_event_id,
        touch_events.device_category as last_touch_device_category,
        touch_events.country as last_touch_country,
        coalesce(touch_events.touch_channel, 'Direct') as last_touch_channel,
        touch_events.touch_campaign as last_touch_campaign,
        touch_events.touch_medium as last_touch_medium,
        touch_events.touch_source as last_touch_source,
        touch_events.gclid as last_touch_gclid,
        touch_events.campaign_id as last_touch_campaign_id,
        touch_events.campaign_name as last_touch_campaign_name,
        touch_events.ad_group_id as last_touch_ad_group_id,
        touch_events.ad_group_name as last_touch_ad_group_name

    from conversion_events
        left join conversion_attributions
            on conversion_events.event_id = conversion_attributions.conversion_event_id
        left join touch_events
            on conversion_attributions.touch_event_id = touch_events.event_id
        left join sessions
            on conversion_events.session_id = sessions.session_id
    
    -- Deduplicate by business identifier (keep first conversion if multiple events exist)
    qualify 1 = row_number() over (
        partition by conversion_events.business_identifier 
        order by conversion_event_timestamp asc
    )
)

select * from final
```

**Join Logic Explanation**:
1. Start with your conversion events
2. LEFT JOIN to `tasman_mta__attributed_conversions` to get attribution metrics
3. LEFT JOIN to touch events to enrich with full touch details
4. LEFT JOIN to sessions for fallback data (when no touch is attributed)

**Key Output Field Categories**:
- **Conversion event details**: Timestamp, event name, IDs, business identifiers
- **Attribution metrics**: Model ID, conversion share, touch count, sequence positions, time intervals
- **Last touch details**: Full marketing attribution context from the attributed touch event

**Understanding Conversion Share**:

The `conversion_share` field represents the contribution that a specific touch made to a conversion. In a last-touch attribution model, this will be `1.0` (100%) for the attributed touch. In multi-touch models, the share is split across multiple touches according to your attribution rules.

```sql
conversion_attributions as (
    select *
    from {{ ref("tasman_mta__attributed_conversions") }}
    where conversion_share > 0 or touch_event_id is null
)
```

This filter is important because:
- `conversion_share > 0` captures all touches that received attribution credit
- `touch_event_id is null` captures unattributed conversions (where no touch was found within the attribution window)

By including both conditions, you ensure every conversion appears in your output, whether attributed or not.

**Handling Direct Traffic & Unattributed Conversions**:

When a conversion cannot be attributed to any marketing touch (either because no touches exist within the attribution window, or all touches were filtered out by your touch rules), you need a fallback strategy:

```sql
coalesce(touch_events.touch_channel, 'Direct') as last_touch_channel
```

This pattern assigns unattributed conversions to 'Direct' as a default channel. This is a common convention in marketing analytics—if there's no clear signal about where the traffic came from, we classify it as direct traffic.

**Why this makes sense**:
- It ensures every conversion has a channel assignment (no NULLs in reporting)
- 'Direct' is semantically appropriate for "unknown origin"
- It separates unattributed conversions from truly attributed direct traffic (if you choose to include direct traffic in your touch events)
- It provides a clear metric for attribution coverage (high 'Direct' percentage = low attribution coverage)

**Alternative Approaches**:
- Use `'Unattributed'` instead of `'Direct'` for clearer distinction
- Use `'Unknown'` or `'(not set)'` following analytics platform conventions
- Keep as NULL and handle in your BI layer

The key is consistency—choose a convention and apply it across all your attribution output models.

**Deduplication**: Use `QUALIFY` with `row_number()` to ensure one row per business identifier (e.g., transaction ID, booking reference, lead ID)



## Troubleshooting

### Issue: No Attributed Conversions

**Possible Causes**:
1. `touch_rules.csv` filtering out all touches ([see Touch Rules](configuration.md#touch-rules))
2. `attribution_windows.csv` window too short ([see Attribution Windows](configuration.md#attribution-windows))
3. `conversion_rules.csv` not matching any conversions ([see Conversion Rules](configuration.md#conversion-rules))
4. Upstream models not running

**Debugging**:
```sql
-- Check touch events exist
SELECT COUNT(*) FROM {{ ref('dmn_web_touch_events') }}

-- Check conversion events exist
SELECT COUNT(*) FROM {{ ref('dmn_web_conversion_events') }}

-- Check MTA output
SELECT COUNT(*) FROM {{ ref('tasman_mta__attributed_conversions') }}
```

---

### Issue: Duplicate Conversions in Output

**Cause**: Multiple attribution models or windows configured

**Check**:
```sql
SELECT 
    model_id,
    att_window,
    COUNT(*) as row_count
FROM {{ ref('tasman_mta__attributed_conversions') }}
GROUP BY 1, 2
```

**Solution**: Filter downstream models to specific `model_id` and `att_window`, or deduplicate using `QUALIFY`.

For more on configuring multiple models, see [Configuring the Models](configuration.md#configuring-the-models).

---

### Issue: Attribution Rate Too Low

**Possible Causes**:
1. Attribution window too short
2. Touch rules too restrictive
3. Identity resolution issues (missing `user_id`)
4. Cookie consent issues

**Investigation**:
```sql
-- Check conversion events with missing user_id
SELECT COUNT(*) 
FROM {{ ref('dmn_web_events') }}
WHERE event_name = 'purchase'
  AND user_id IS NULL

-- Check touch events by channel
SELECT 
    touch_channel,
    COUNT(*) as touch_count
FROM {{ ref('dmn_web_touch_events') }}
GROUP BY 1
ORDER BY 2 DESC
```

---

### Issue: Incremental Models Not Updating

**Cause**: Incremental lookback window too short or identity backstitching not working

**Check**:
```sql
-- Check max timestamp in incremental models
SELECT MAX(event_timestamp) FROM {{ ref('dmn_web_touch_events') }}
SELECT MAX(event_timestamp) FROM {{ ref('dmn_web_conversion_events') }}

-- Check identity changes
SELECT COUNT(*) FROM {{ ref('int_identity_changes') }}
```

**Solution**: 
- Increase `incremental_load_lookback_window` in `dbt_project.yml`
- Run with `--full-refresh` flag to rebuild from scratch

---
