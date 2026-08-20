## Hardware Implementation of a 64-Point FFT Based on a Folded SDF Architecture

中文版：[report.md](report.md)

**School of Integrated Circuits — Guo Sufeng, 231880273**

## Abstract

This report describes the hardware implementation flow of a 64-point radix-2 DIT FFT. A fully parallel flash reference model was first built to validate the algorithm. The datapath was then folded into a streaming RTL design using the folding and SDF concepts described by Parhi. The design uses Q1.15 fixed-point arithmetic, an input bit-reversal buffer, six SDF stages, and a unified normalization strategy. A joint SystemVerilog testbench and Python/NumPy verification flow provides one-click simulation, log collection, and error statistics. Synthesis and implementation results on a Virtex-7 device show reductions of approximately 70–98% in the main resource categories compared with the fully parallel reference, while the routed SDF implementation has 1.6 ns of positive slack under the 100 MHz clock constraint. The result demonstrates that a folded FFT can preserve algorithmic equivalence while offering a practical hardware cost for larger or reconfigurable DSP systems.

## Contents

- [1. Introduction](#1-introduction)
- [2. FFT algorithm](#2-fft-algorithm)
- [3. Design motivation and optimization](#3-design-motivation-and-optimization)
- [4. System architecture](#4-system-architecture)
- [5. RTL design](#5-rtl-design)
- [6. Verification and simulation](#6-verification-and-simulation)
- [7. Resource and timing analysis](#7-resource-and-timing-analysis)
- [8. Conclusion](#8-conclusion)

## 1. Introduction

The Fast Fourier Transform (FFT) is one of the most important and widely used algorithms in digital signal processing. By exploiting the periodicity and symmetry of the complex exponential, it reduces the direct DFT complexity from (O(N^2)) to (O(N\log_2N)).

FFT hardware is used in communications such as OFDM, radar and sonar, image processing, and audio-spectrum analysis. These applications require high throughput, low power, and efficient use of hardware resources. Hardware implementations can provide better real-time performance and energy efficiency than software, but they also require careful choices of architecture, resource sharing, and timing schedule.

This project uses a 64-point FFT as a case study. It implements both a fully parallel FFT for functional reference and a folded SDF FFT for resource-efficient hardware, then compares the two designs. The final SDF implementation is regular, stream-oriented, and suitable as a VLSI DSP building block.

## 2. FFT algorithm

### 2.1 Discrete Fourier Transform

For an (N)-sample sequence (x[n]), the DFT is

```text
X[k] = Σ(n=0…N-1) x[n] · exp(-j·2π·k·n/N),  k = 0, 1, …, N-1
```

Direct evaluation requires (N^2) complex multiply-accumulate operations. The cost becomes impractical for larger (N) and high-rate real-time systems.

### 2.2 FFT principle

An FFT recursively decomposes one large DFT into smaller DFTs and reuses repeated terms. For (N=2^M), radix-2 FFT divides the data into even and odd subsequences and combines them with butterfly operations. A butterfly consists of complex additions/subtractions and a twiddle-factor rotation.

### 2.3 DIT structure

This project uses a decimation-in-time (DIT) structure:

- input data is reordered and decomposed in the time domain;
- multiple butterfly stages are cascaded;
- the output is produced in natural order.

A 64-point radix-2 DIT FFT requires (log_2(64)=6) stages. The regular dataflow of these stages makes the algorithm well suited to folding and streaming.

## 3. Design motivation and optimization

### 3.1 Initial fully parallel architecture

The first implementation instantiates every butterfly in every FFT stage and loads the 64-point input as a parallel array. It completes the transform in very few clock cycles and is easy to compare with the mathematical algorithm.

Its disadvantages are equally clear: the number of butterflies and complex multipliers grows rapidly, the combinational logic and routing become large, and the design consumes too many FPGA/ASIC resources for practical deployment. The flash architecture is therefore retained as a functional reference and comparison baseline.

### 3.2 Why folding is needed

Folding reuses a hardware operator at different times without changing the algorithmic function. The cost is additional latency, but the benefit is a large reduction in area and power. FFTs have a regular data-flow graph, so they are especially suitable for this optimization.

The project reschedules the parallel butterfly graph into a stream-oriented datapath in which arithmetic units are reused over time. This produces the folded FFT architecture.

### 3.3 From parallel FFT to SDF FFT

Each FFT stage is mapped to one Single-Delay Feedback (SDF) stage:

- one butterfly unit is retained per stage;
- a feedback delay line stores the samples needed for the next butterfly pair;
- the twiddle factor is selected according to the current sample phase.

The resulting circuit processes one sample per cycle after the pipeline is filled. A frame takes longer than in the fully parallel design, but the hardware cost is greatly reduced.

### 3.4 Comparison summary

The two architectures serve different purposes:

- the fully parallel architecture is a direct functional reference;
- the folded SDF architecture meets realistic hardware resource constraints;
- both implement the same FFT mathematically, while their area, latency, and timing characteristics differ.

This top-down flow—algorithm first, then resource-driven rescheduling—follows the standard VLSI DSP design methodology.

## 4. System architecture

### 4.1 Radix-2 DIT FFT

The 64-point transform is decomposed into six radix-2 butterfly stages. DIT splits the time-domain sequence into even and odd parts and combines them with twiddle factors.

### 4.2 Folding and SDF according to Parhi

The design applies two related ideas:

- **Folding:** time-multiplex butterflies and multipliers to reduce hardware area.
- **SDF:** use one butterfly and one feedback delay line per FFT stage to preserve a streaming schedule.

For stage (k), the delay length is (2^k). The architecture maintains one-sample-per-cycle throughput while using far fewer arithmetic units than a fully parallel implementation.

### 4.3 Design goals and constraints

The design targets a fixed 64-point FFT with Q1.15 input and output, streaming complex samples, and a throughput of one sample per cycle. The SDF architecture trades latency for area efficiency and avoids the excessive butterfly, multiplier, and register count of a fully parallel FFT.

### 4.4 Top-level architecture

The top level contains:

- an input reorder buffer for bit reversal;
- six cascaded DIT SDF stages;
- a twiddle-factor ROM;
- complex multiplication and butterfly add/subtract units.

Samples enter sequentially, pass through the six stages, and leave as the FFT result stream. The RTL implementation is in [`sim/fft64_model.sv`](sim/fft64_model.sv), and the testbench instance and streaming ports are in [`sim/tb_fft64.sv`](sim/tb_fft64.sv).

### 4.5 Data representation

Inputs and outputs use signed Q1.15 values. Internal products and sums retain extra width before truncation. The final output is normalized by 64 so that it matches the Python reference model.

## 5. RTL design

### 5.1 Overall SDF implementation

The six radix-2 DIT stages each reuse one butterfly through a feedback delay line. Natural-order input samples first pass through the internal reorder buffer and then move through the SDF chain. Each stage handles different butterfly pairs at different times, producing a complete 64-point spectrum at the output.

### 5.2 Input reorder buffer

The DIT schedule requires a particular input order. The design hides this requirement inside a double-bank buffer:

- one memory bank receives the current frame;
- the other bank reads the previous frame in bit-reversed order;
- the banks switch roles at a frame boundary.

This allows bit reversal without reducing the external sample rate. The SystemVerilog listing in the Chinese section shows the `bit_rev`, bank-select, and read/write control logic.

### 5.3 SDF stage structure

Each DIT SDF stage contains:

- one complex butterfly (add/subtract);
- a feedback line of length (2^k);
- a twiddle selection and complex multiplier;
- control logic that distinguishes pass-through samples from feedback samples.

During the first (2^k) active cycles, samples are loaded into the delay line. During the next (2^k) cycles, the new sample and delayed sample form a butterfly pair. The same operator is therefore reused across the complete frame.

### 5.4 Twiddle factors and fixed-point arithmetic

Twiddle factors are stored in a Q1.15 ROM. Complex products are calculated at an extended width to avoid intermediate overflow, then truncated back to the interface width. The final stage applies the common 1/64 normalization used by the NumPy model.

### 5.5 Comparison with the fully parallel FFT

The fully parallel version can calculate the transform in very few cycles, but its resource cost is large. The folded SDF version increases latency while reducing butterflies, multipliers, registers, and I/O. It keeps one-sample-per-cycle throughput and is therefore more appropriate for an FPGA or ASIC datapath.

The main SDF modules are:

- `fft64_dit_sdf` / `dit_sdf_stage`: six reusable butterfly stages with delay lines;
- `input_reorder_buffer`: double-bank bit-reversal input buffering.

Relative to the parallel graph, the folded implementation reduces the multiplier count from approximately (O(N\log N)) to (O(\log N)), adds frame latency, and presents a compact streaming interface.

## 6. Verification and simulation

### 6.1 SystemVerilog testbench

The testbench supports five input modes—pulse, sine, square, random, and file input. It feeds one complex sample per cycle, captures samples when `valid_out` is asserted, and writes the 64 complex outputs to `output_vivado.txt`. The original report includes representative input and output console excerpts.

### 6.2 Python/NumPy co-verification

The Python checker uses `numpy.fft.fft(x)/64` as the floating-point golden model. Its stimulus generator, Q1.15 conversion, and input modes are aligned with the SystemVerilog testbench. It reports maximum and mean absolute error, prints point-by-point differences, and produces magnitude and phase comparison plots. Near-zero bins are thresholded before phase inspection because tiny numerical noise can cause large phase swings there.

### 6.3 Automated simulation flow

`run_fft64_all.py` performs the following steps:

1. launch Vivado XSim in batch mode;
2. collect Vivado logs into a timestamped directory;
3. invoke `py/check_fft64.py` for NumPy comparison and plots.

The example sine-wave run in the original section reports a maximum absolute error of approximately `6.82e-05` and a mean absolute error of approximately `5.08e-06`. The fixed-point error is therefore within the expected range for this design.

## 7. Resource and timing analysis

The two architectures were synthesized and analyzed on a Xilinx Virtex-7 `xc7vx690t-ffg1761-2` device. The flash design is the fully parallel reference; the SDF design is the folded implementation.

### 7.1 FPGA resource comparison

| Resource | Fully parallel FFT | SDF FFT | Reduction |
| --- | ---: | ---: | ---: |
| Slice LUTs | 12,289 | 2,158 | 82.4% |
| Slice registers | 15,496 | 4,830 | 68.8% |
| DSP48E1 | 768 | 24 | 96.9% |
| BRAM | 0 | 0 | — |
| BUFG | 1 | 1 | — |
| I/O ports / bonded IOB | 4,100 | 68 | 98.3% |

The parallel design exposes the complete 64-point arrays at its top level. Its 4,100 bonded IOBs exceed the device's 850 available I/Os, so it cannot complete physical implementation. Its main value is algorithmic and functional comparison.

The SDF design reuses one complex multiplier per stage, uses only 24 DSP48E1 blocks, reduces LUT and register usage to roughly one fifth of the reference, and exposes a compact 68-pin streaming interface. This is the practical benefit of folding: trading latency for area.

### 7.2 SDF timing performance

The routed SDF implementation uses a 100 MHz clock (10 ns period). The key results are:

| Metric | Result |
| --- | ---: |
| WNS (worst negative slack) | **+1.631 ns** |
| TNS | 0.000 ns |
| WHS | 0.084 ns |
| Setup violations | None |
| Hold violations | None |

The critical path starts in an FFT-stage register, passes through a DSP48E1 complex multiply, fixed-point add/subtract logic (including CARRY4), and LUT control logic, and ends at a delay-line register. This matches the expected SDF datapath and leaves room for additional pipelining or frequency optimization.

### 7.3 Theoretical parallel timing versus engineering reality

A fully parallel design may produce an idealized post-synthesis timing report, but its excessive I/O count prevents successful placement and routing. That timing number is therefore not an engineering result. The SDF design completes synthesis, placement, routing, and timing analysis with real physical constraints, so its timing result is the meaningful deployment metric.

### 7.4 Overall comparison

The fully parallel architecture is clear and useful for algorithm validation, but it is too expensive for the target FPGA. The folded SDF architecture follows the VLSI DSP folding model, keeps one-sample-per-cycle throughput, greatly reduces resources, and satisfies the saved FPGA timing and physical constraints.

## 8. Conclusion

Combining VLSI DSP theory with RTL implementation demonstrates the efficiency and practicality of a folded SDF FFT. The architecture is a strong fit for resource-constrained systems and provides a foundation for larger FFTs and reconfigurable DSP modules.

## Appendix: Included artifacts

- `vivado_project/FFT64_SIM/FFT64_SIM.xpr`
- `vivado_project/FFT64_SIM/utilization_report_flash_virtex.txt`
- `vivado_project/FFT64_SIM/utilization_report_sdf_virtex.txt`
- `README.md`
- `sim/fft64_model.sv`
- `sim/tb_fft64.sv`
