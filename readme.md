# Multi-Touch Attribution Engine

## Table of Contents
- [Multi-Touch Attribution Engine](#multi-touch-attribution-engine)
  - [Table of Contents](#table-of-contents)
  - [What is Multi-Touch Attribution?](#what-is-multi-touch-attribution)
  - [Adding the dbt package](#adding-the-dbt-package)
  - [Configuring the Engine](#configuring-the-engine)
  - [Engine Outputs](#engine-outputs)
  - [Performance Tracking](#performance-tracking)
  - [Current Limitations](#current-limitations)

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

Instructions on how to configuration the MTA Engine can be found [here](docs/configuration.md)

## Engine Outputs

The engine has two primary output models, attributed touches and attributed conversions.   
- **Attributed Touches** contains all filtered touches (based on the touch rules) across all attribution models that have been attributed to a conversion. Where touches have been attributed, there will be a `conversion_event_id` for that `touch_event_id`, as well as a conversion share value if appropriate.
- **Attributed Conversions** is this inverse of the attributed touches and contains all filtered conversions (based on the conversion rules) across all attribution models, whether or not they have attributed to a touch. Each `conversion_event_id` may appear once all multiple times depending on the number of attributed touches. Where `touch_event_id` is null, this indicates that the conversion is unattributed.


## Performance Tracking

Its unlikely that optimal attribution results will be achieved during the initial implementation of this engine - this is because the quality of the outputs are entirely dependent on the quality of the inputs along with tuning of the configurations. As such, an `attribution_performance_history` model has been added that will keep track of each time the attribution engine is run, and collect useful statistics that can help accelerate the implementation as well as monitor key metrics such as attribution rate.

## Current Limitations
1. Handling conversion shares where the total number of touches is lower than the number of specs. For example, if there are only 2 touches but 3 attribution rule specs, then the total conversion shares will not sum to 100%. This needs to be accounted for when analysing the outputs.
2. Conversion shares are assigned at the touch level, not the session level. This means that the inputs into the engine need to account for this. It is therefore most often the case that internal touches should be filtered.