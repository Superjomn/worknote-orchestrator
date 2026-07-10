# DP Sweep Study

We are measuring rollout throughput as a function of data-parallel width (`dp`)
from a known-good baseline, to find where throughput stops scaling.

## Setup

The baseline config is validated and recorded in shared memory.

<<@memory summarize the working baseline config and its throughput from memory>>

## Results

Each sweep point reuses the baseline recipe with only `dp` changed.

- dp=2: <<@run sweep point dp=2, collect throughput>>
- dp=4: <<@run sweep point dp=4, collect throughput>>
- dp=8: <<@run sweep point dp=8, collect throughput>>

## Conclusion

_(to be written once all sweep points are in)_
