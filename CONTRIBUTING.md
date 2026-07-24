# Contributing

Hardware reports and patches are welcome.

Please include:

- Exact laptop model and CPU/GPU configuration.
- DOS version and memory-manager configuration.
- The requested PWM value and all program output.
- Whether testing used `BLCSET` or `BLCINIT`.

Do not test direct MMIO changes on unsupported hardware without a recovery boot method. Keep source changes compatible with Borland TASM syntax unless a separate port is clearly identified.
