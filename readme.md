<a target="_blank" href="https://tasman.ai">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/tasman_light.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/assets/tasman_dark.png">
  <img alt="Tasman Logo" src="tasman_light.png" width='500'/>
</picture>
</a>

> We are the boutique analytics consultancy that turns disorganised data into real business value.

# Multi-Touch Attribution Engine

**Key Features:**
- 🔩 Boolean-algebra based filter definitions, allowing fine control of the touches and conversions that are analysed for each attribution model without editing any SQL.
- 🪛 Reconfigurable positional and time-based attribution models.
- 🔀 Multiple concurrent models, enabling robust multi-model analyses.
- ⏰ Fine-grain attribution window control.
- ➕ Fully incremental materialisations
- ❄️ Custom warehouse selection (Snowflake only)


## What is Multi-Touch Attribution? 🤨

Multi-touch attribution is a method of marketing measurement that accounts for all the touchpoints on the customer journey and designates a certain amount of credit to each channel. This enables marketers to analyse the value that each touchpoint has on driving a conversion.

The core functionality of an attribution engine is its ability to match touches to conversions based on a series of rules, known as 'attribution models'.

>Examples of attribution models that can be configured with this engine include:
>- Last touch - 100% conversion credit is applied to the touch point immediately before the conversion event
>- First touch - 100% conversion credit is applied to the earliest occuring touch point
>- U-shaped - 40% conversion credit is given to both first and last touches, with the remaining 20% split across all others

🧠 For more information, [Segment has written an article](https://segment.com/academy/advanced-analytics/an-introduction-to-multi-touch-attribution/) introducing the topic and the most common models.

## Configuring the Engine ⚙️

Instructions on how to configure the MTA Engine can be found [here](docs/configuration.md).

## Engine Outputs 🔥

The engine has two primary output models, attributed touches and attributed conversions.   
- [**`attributed_touches`**](models/tasman_mta__attributed_touches.sql) contains all filtered touches (based on the touch rules) across all attribution models that have been attributed to a conversion. Where touches have been attributed, there will be a `conversion_event_id` for that `touch_event_id`, as well as a conversion share value if appropriate.
- [**`attributed_conversions`**](models/tasman_mta__attributed_conversions.sql) is this inverse of the attributed touches and contains all filtered conversions (based on the conversion rules) across all attribution models, whether or not they have attributed to a touch. Each `conversion_event_id` may appear once all multiple times depending on the number of attributed touches. Where `touch_event_id` is null, this indicates that the conversion is unattributed. This is the model that should be used in downstream models to analyse attribution performance.

## Performance Tracking 🚀

Attribution is tricky and it'ss unlikely that optimal results will be achieved during the initial implementation of this engine - this is because the quality of the outputs are entirely dependent on the quality of the inputs along with tuning of the configurations. As such, an [`performance_history`](models/tasman_mta__performance_history.sql) model has been added that will keep track of each time the attribution engine is run, and collect useful statistics that can help accelerate the implementation as well as monitor key metrics such as attribution rate.

## Current Limitations ⚠️

- Handling conversion shares where the total number of touches is lower than the number of specs. For example, if there are only 2 touches but 3 [attribution rule specs](docs/configuration.md#attribution-rules), then the total conversion shares will not sum to 100%. This needs to be accounted for when analysing the outputs.

## Supported Data Warehouses
This package currently supports Snowflake and BigQuery targets.

## Contact
This package has been written and is maintained by [Tasman Analytics](https://tasman.ai).

If you find a bug, or for any questions please open an issue on GitHub.
