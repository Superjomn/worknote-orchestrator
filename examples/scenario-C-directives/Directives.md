# Batch-Size Latency Study

We are measuring inference latency as a function of batch size (`bs`), running each point
on a specific machine (working directory). The `@dir:` directives pin where each job runs.

## Setup

The baseline recipe is validated and recorded in shared memory.

<<@memory quote the best validated throughput from memory>>

## Results

Each point measures latency at a fixed batch size in its assigned workdir.

- bs=32 (machine alpha): <<@dir:examples/scenario-C-directives/workdir-alpha @run measure latency at bs=32>>
- bs=64 (machine beta): <<@dir:examples/scenario-C-directives/workdir-beta @run measure latency at bs=64>>
- bs=128 (default machine): <<@run measure latency at bs=128>>

## Conclusion

_(to be written once all batch-size points are in)_
