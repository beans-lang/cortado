# Table benchmark

From the Cortado directory:

```sh
BEANS_RUNTIME=../../beans/runtime/beans_rt.c \
BEANS_STDLIB=../../beans/stdlib/std \
BEANS_ENCODING=../../beans/runtime/encoding \
BEANS_NET=../../beans/runtime/net \
BEANS_LOG=../../beans/runtime/log \
../../beans/build/beansc build examples/rendered/benchmarks/table/main.b -o build/table-benchmark
./build/table-benchmark
```

Build the local engine with `python3 tools/prepare_skia.py` first if needed.
Run the compiled binary while other builds are idle. Interpreter timing does not
measure native app performance.

The test scrolls the gallery's 10,000-row table through 120 four-pixel steps at
840×760 points and 2× scale using software rendering. It prints mean drawing and
fresh snapshot times, the longest combined step, steps over 16.67 ms, and source
cell reads. It then times readback plus native Canvas presentation. This is a timing tool, not a pass/fail frame-rate test.

The scroll loop uses synchronous Scene calls. It does not include display latency
or Window wheel batching. `examples/rendered/tests/window_scroll` checks that a
wheel burst waits for one frame, preserves boundary ordering, and settles rows
before a following double-click. `examples/rendered/tests/table` checks visible
row reuse, editor identity, commit/cancel, and keyboard editing.

Local macOS reference, 18 September 2026, three quiet runs of the workload above:

| Measure | Before | After |
| --- | ---: | ---: |
| Mean render time (median of runs) | 2.82 ms | 1.48 ms |
| Source cell reads | 3,120 | 34 |
| Largest render + fresh snapshot step | 13.38 ms | 4.90 ms |

These timings exclude native presentation and display latency. All three runs
stayed below 16.67 ms for that measured section both before and after the change.
A separate, alternated fresh-versus-persistent-buffer test found persistent
readback slower on this machine (7.58–8.02 ms versus 6.43–6.74 ms including native
presentation), so Window keeps the fresh snapshot path. Frame batching and row
caching provide the performance improvement.
