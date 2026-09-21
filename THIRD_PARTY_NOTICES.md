# Third-Party Notices

## macmon (MIT)

Portions of `Packages/TemperatureCore/Sources/SensorBridge/SensorBridge.c` adapt the Apple SMC read-only ABI from [macmon](https://github.com/vladkens/macmon) at commit `6919d7781b6c55a6e3bedff83a210435837e1dfe` (`src_lib/sources.rs`).

Modifications for Temperature monitoring:

- Production package path under `Packages/TemperatureCore`
- SMC-only surface in revision 2 (`open` / key index / key info+read / `close`)
- Fan control, SMC writes, and privilege escalation paths omitted

MIT License

Copyright (c) 2024 vladkens

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
