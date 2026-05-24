# MTA Feature Requests & Enhancement Opportunities

This document outlines potential enhancements to the Tasman MTA package that could improve attribution accuracy and flexibility.

---

## Table of Contents
- [Feature Request 1: Per-Conversion Share Calculation](#feature-request-1-per-conversion-share-calculation)
- [Feature Request 2: Multi-Conversion Attribution](#feature-request-2-multi-conversion-attribution)

---

## Feature Request 1: Per-Conversion Share Calculation

**Priority**: Medium (Bug?)

**Location**: `tasman_mta__attributed_touches.sql` line 301 in the Tasman MTA package

---

### Current Behavior

The `conversion_share` field is calculated by dividing the attribution share across all touches for a user's lifetime, rather than per individual conversion.

**Current Logic**:
```sql
conversion_shares.share / count(matched_groups.touch_event_id) over (
    partition by matched_groups.touch_user_id, matched_groups.model_id, matched_groups.spec
) as conversion_share
```

**What This Means**:
- For a user with 3 conversions (each with 1 attributed touch), each touch receives a `conversion_share` of 0.333 (1/3)
- The share is split across the user's entire conversion history, not per conversion

**Example**:
```
User makes 3 purchases over their lifetime, each with 1 attributed touch:
- Purchase 1: conversion_share = 0.333 (1 touch ÷ 3 total user touches)
- Purchase 2: conversion_share = 0.333 (1 touch ÷ 3 total user touches)
- Purchase 3: conversion_share = 0.333 (1 touch ÷ 3 total user touches)
```

---

### Desired Behavior

Calculate `conversion_share` per individual conversion, so each conversion's touches sum to the configured share value (typically 1.0 for single-touch models).

**Proposed Logic**:
```sql
conversion_shares.share / count(matched_groups.touch_event_id) over (
    partition by matched_groups.conversion_event_id, matched_groups.model_id, matched_groups.spec
) as conversion_share
```

**What This Would Mean**:
- For a last-touch model, each attributed touch receives `conversion_share = 1.0`
- For a multi-touch model (e.g., 40/20/40), shares sum to 1.0 per conversion
- Repeat purchasers are treated the same as first-time purchasers

**Example**:
```
User makes 3 purchases over their lifetime, each with 1 attributed touch:
- Purchase 1: conversion_share = 1.0 (1 touch ÷ 1 touch for this conversion)
- Purchase 2: conversion_share = 1.0 (1 touch ÷ 1 touch for this conversion)
- Purchase 3: conversion_share = 1.0 (1 touch ÷ 1 touch for this conversion)
```

---

### Validation Query

To verify current behavior (should return 0 rows for repeat purchasers with share = 1.0):

```sql
-- Check if any repeat purchasers have conversion_share = 1.0
SELECT COUNT(*) as repeat_purchasers_with_share_1
FROM {{ ref('tasman_mta__attributed_touches') }}
WHERE conversion_share = 1.0
  AND touch_user_id IN (
    SELECT touch_user_id
    FROM {{ ref('tasman_mta__attributed_touches') }}
    GROUP BY touch_user_id
    HAVING COUNT(DISTINCT conversion_event_id) > 1
  )
```

---

### Implementation Notes

**Change Required**: Single line modification in `tasman_mta__attributed_touches.sql`

**Testing Considerations**:
- Verify single-touch models (first-touch, last-touch) produce `conversion_share = 1.0`
- Verify multi-touch models (U-shaped, W-shaped) produce shares that sum to 1.0 per conversion
- Confirm no impact on other attribution fields (`convert_seq_down`, `interval_convert`, etc.)


---

## Feature Request 2: Multi-Conversion Attribution

**Status**: Enhancement opportunity identified

**Priority**: Low (edge case scenario)

**Location**: `tasman_mta__attributed_touches.sql` line 63 in the Tasman MTA package

---

### Current Behavior

Each touch is attributed to only its **first subsequent conversion**. If multiple conversions occur after a single touch, only the first conversion receives attribution.

**Current Logic**:
```sql
first_value(conversion_event_id) over (
    partition by touch_user_id, touch_event_id, model_id, touch_category 
    order by conversion_timestamp 
    rows unbounded preceding
)
```

**What This Means**:
- A touch can only "claim" one conversion
- Subsequent conversions in the same session appear unattributed (or attributed to 'Direct')
- Each user journey is treated as: touch → first conversion (attributed), subsequent conversions (not attributed to that touch)

**Example Scenario**:
```
User Journey:
1. PPC ad click (touch)
2. Enquiry 1 (conversion) ← Attributed to PPC ✓
3. Enquiry 2 (conversion) ← Not attributed to PPC ✗ (appears as 'Direct')
4. New page view (touch)
5. Purchase (conversion) ← Attributed to page view ✓
```

**Real-World Edge Case**:
```
User Journey:
1. PPC ad click (touch)
2. Purchase 1 (conversion) ← Attributed to PPC ✓
3. Purchase 2 (conversion) ← Not attributed to PPC ✗ (appears as 'Direct')
```

---

### Desired Behavior

Allow a single touch to be attributed to multiple conversions within the attribution window, giving credit to the original marketing touchpoint for all conversions it influences.

**Proposed Approach**:
- Remove the `first_value()` constraint that limits each touch to one conversion
- Attribute a touch to all subsequent conversions within the attribution window
- Maintain proper deduplication logic to handle legitimate duplicate events

**What This Would Mean**:
- A PPC click that leads to multiple purchases would receive credit for all purchases
- More accurate representation of marketing effectiveness for high-value customers
- Better attribution for multi-conversion sessions

**Example Scenario**:
```
User Journey:
1. PPC ad click (touch)
2. Enquiry 1 (conversion) ← Attributed to PPC ✓
3. Enquiry 2 (conversion) ← Attributed to PPC ✓
4. New page view (touch)
5. Purchase (conversion) ← Attributed to page view ✓
```

**Edge Case Resolution**:
```
User Journey:
1. PPC ad click (touch)
2. Purchase 1 (conversion) ← Attributed to PPC ✓
3. Purchase 2 (conversion) ← Attributed to PPC ✓
```

---

### Benefits

1. **Accurate channel effectiveness**: Marketing channels get full credit for all conversions they drive
2. **Better ROAS calculation**: Multi-purchase sessions correctly attribute revenue to the originating channel
3. **Improved customer journey understanding**: See the full impact of a single marketing touchpoint
4. **Reduced "Direct" inflation**: Fewer conversions incorrectly classified as direct traffic

---

### Challenges & Considerations

**Challenge 1: Duplicate Event Handling**
- **Issue**: GA4 can send duplicate purchase events for a single transaction
- **Risk**: Over-attribution if duplicates aren't properly handled
- **Mitigation**: Ensure deduplication logic based on business identifiers (e.g., `booking_reference`, `transaction_id`)

**Challenge 2: Attribution Window Complexity**
- **Issue**: Need to ensure attribution window logic applies correctly to each conversion
- **Solution**: Maintain per-conversion window checks rather than per-touch window checks

**Challenge 3: Package Stability**
- **Issue**: This is a core logic change affecting all attribution calculations
- **Requirement**: Extensive testing across single-touch and multi-touch models

**Challenge 4: Backward Compatibility**
- **Issue**: Results would differ from current implementation
- **Solution**: Consider making this an optional configuration flag

---

### Implementation Notes

**Change Required**: 
- Modify conversion assignment logic in `tasman_mta__attributed_touches.sql`
- Add robust deduplication based on business identifiers
- Maintain attribution window validation per conversion

**Testing Considerations**:
- Verify single-conversion journeys produce identical results to current implementation
- Test multi-conversion scenarios with various attribution windows
- Confirm duplicate event handling works correctly
- Validate single-touch and multi-touch models both work as expected

**Alternative Approach**:
- Add a configuration flag: `allow_multi_conversion_attribution: true/false`
- Default to `false` (current behavior) for backward compatibility
- Allow projects to opt-in to new behavior

**Timeline**: Enhancement opportunity for future package release (not currently planned)

