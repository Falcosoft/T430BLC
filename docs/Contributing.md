# Contributing

Contributions are welcome.

## Reporting hardware

Please include:

- ThinkPad model
- CPU
- Intel graphics generation
- Internal panel resolution
- External display connection
- DOS version
- HIMEM / EMM386 status
- Utility and command used
- Complete console output
- Visible behaviour

## Coding style

- Borland TASM compatible
- `.model tiny`
- `.386p`
- conservative register writes
- preserve existing behaviour unless verified on hardware

## Pull requests

Prefer small, focused changes. New hardware support should include diagnostic
output demonstrating the behaviour that motivated the change.

## Attribution

The project openly acknowledges its collaborative development between
Zoltán Bacskó (Falcosoft) and OpenAI ChatGPT.
