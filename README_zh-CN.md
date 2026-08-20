# 64 点 FFT 的硬件实现与优化

[English](README.md)

本仓库使用 SystemVerilog 实现并验证一个 **64 点、基 2、按时间抽取（DIT）的 FFT**。项目先以全并行（flash）结构作为功能参考，再依据 Keshab K. Parhi 的 VLSI DSP 折叠思想，将数据通路优化为串流式 **单延迟反馈（SDF）结构**。

仓库保留 RTL、Vivado 工程、定点 Python 模型、激励生成器、波形图、日志和实现报告，方便从算法结果一路追溯到 FPGA 资源和时序结果。

## 项目亮点

- 64 点 radix-2 DIT FFT，共 6 级级联 SDF stage。
- 串流接口：完成帧启动和输入缓冲后，支持每周期输入一个复数采样。
- 输入/输出统一采用 Q1.15 定点格式，内部保留额外位宽，并统一除以 64 归一化。
- 集成输入位反转缓冲、旋转因子 ROM、复数乘法器、蝶形加减和各级延迟线。
- 支持脉冲、正弦、方波、确定性随机数和文件输入五种激励模式。
- Vivado XSim 与 Python/NumPy 联合验证，自动输出误差统计、幅度图和相位图。
- 仓库内保留综合、实现、功耗、时序和示例输出，未安装 Vivado 也可以先检查结果。

## 架构概览

```text
复数输入流
    │
    ▼
双 Bank 输入重排缓冲（位反转）
    │
    ▼
SDF stage 0（延迟 1）→ … → SDF stage 5（延迟 32）
    │
    ▼
Q1.15 FFT 输出流 + valid_out
```

64 点数据帧依次经过 6 级 radix-2 蝶形和旋转因子运算。SDF 通过时间复用运算单元换取帧延迟，从而显著降低全并行结构的硬件开销。

本项目实现的变换为：

```text
X[k] = (1/64) · Σ(n=0…63) x[n] · exp(-j·2π·k·n/64)
```

## 仓库结构

| 路径 | 用途 |
| --- | --- |
| [`fft64_sim/sim/fft64_model.sv`](fft64_sim/sim/fft64_model.sv) | 当前 testbench 和 Vivado 仿真使用的主 SDF RTL |
| [`fft64_sim/sim/tb_fft64.sv`](fft64_sim/sim/tb_fft64.sv) | 自驱动 SDF testbench，生成 `output_vivado.txt` |
| [`fft64_sim/sim/fft64_flash.sv`](fft64_sim/sim/fft64_flash.sv) | 全并行参考结构 |
| [`fft64_sim/sim/fft64_sdf.sv`](fft64_sim/sim/fft64_sdf.sv) | 独立的 SDF 源码变体 |
| [`fft64_sim/py/check_fft64.py`](fft64_sim/py/check_fft64.py) | NumPy 参考、定点转换、误差统计和绘图 |
| [`fft64_sim/scripts/run_sim.tcl`](fft64_sim/scripts/run_sim.tcl) | Vivado 批处理仿真脚本 |
| [`fft64_sim/run_fft64_all.py`](fft64_sim/run_fft64_all.py) | 一键运行 Vivado + Python，并按时间戳归档日志 |
| [`fft64_sim/vivado_project/FFT64_SIM/FFT64_SIM.xpr`](fft64_sim/vivado_project/FFT64_SIM/FFT64_SIM.xpr) | Vivado 工程文件 |
| [`fft64_sim/reports/`](fft64_sim/reports/) | 实现后的资源和时序报告 |
| [`fft64_sim/report.pdf`](fft64_sim/report.pdf) | 项目详细报告 |

仿真目录还有一份更聚焦于运行细节的说明：[`fft64_sim/README.md`](fft64_sim/README.md)。

## 快速开始

### 1. 仅运行 Python 校验

Python 校验需要先存在 Vivado 输出文件，适合检查参考模型并重新生成图表：

```bash
cd fft64_sim
python py/check_fft64.py --input-mode 1 --no-show --save-dir plots
```

### 2. 运行 Vivado 行为仿真

请在 `fft64_sim/` 目录下运行，因为 TCL 脚本使用相对路径：

```bash
vivado -mode batch -source scripts/run_sim.tcl
```

testbench 会在 XSim 工作目录生成 64 行有符号 `real imag` 数据。输出文件的准确位置也由 [`check_fft64.py`](fft64_sim/py/check_fft64.py) 中的 `OUTPUT_FILE` 定义。

### 3. 运行完整流程

```bash
cd fft64_sim
python run_fft64_all.py
```

脚本依次运行 Vivado、将日志归档至 `logs/vivado_run_<timestamp>/`，再执行 NumPy 对比。脚本内的 Vivado 路径是 Windows 默认路径，需要按本机安装位置修改。

## 激励模式

SystemVerilog testbench 与 Python 校验脚本使用相同的模式编号和波形参数。

| `INPUT_MODE` | 激励 | 用途 |
| ---: | --- | --- |
| 0 | `PULSE` | 冲激响应和全频谱 sanity check |
| 1 | `SINE` | 默认单频测试，频率索引由 `WAVE_K` 指定 |
| 2 | `SQUARE` | 谐波和非正弦信号测试 |
| 3 | `RANDOM` | 由共享 LCG 生成的确定性复数序列 |
| 4 | `FROM_FILE` | 从 [`fft64_sim/rt1/input.txt`](fft64_sim/rt1/input.txt) 读取 64 组定点数据 |

请保持 [`tb_fft64.sv`](fft64_sim/sim/tb_fft64.sv) 与 [`check_fft64.py`](fft64_sim/py/check_fft64.py) 中的 `INPUT_MODE`、`WAVE_K`、位宽和幅度配置一致。Python 脚本支持 `--input-mode`、`--save-dir`、`--prefix` 和 `--no-show` 参数。

## 校验输出

- `output_vivado.txt`：XSim 输出的 64 个 Q1.15 复数 FFT 结果。
- `plots/`：运行时生成的幅度和相位叠加图。
- `plots_example/`：已提交的脉冲、正弦、方波和随机激励示例。
- `logs/`：一键脚本收集的带时间戳 Vivado 日志。

校验脚本会打印最大/平均绝对误差、逐点对比，并在观察相位前屏蔽接近零的数值噪声。下面是一个正弦激励示例：

![正弦波幅度对比](fft64_sim/plots_example/fft_mag_compare_sine.png)

## FPGA 结果

下表来自仓库内相同 Virtex-7 器件系列（`7vx690tffg1761-2`）的 Vivado 报告。Flash 为全并行参考结构，SDF 为折叠后的实现结构。

| 指标 | Flash 参考 | SDF 实现 | 降幅 |
| --- | ---: | ---: | ---: |
| Slice LUT | 12,289 | 2,158 | 82.4% |
| Slice 寄存器 | 15,496 | 4,830 | 68.8% |
| DSP48E1 | 768 | 24 | 96.9% |
| Bonded IOB | 4,100 | 68 | 98.3% |

布线后的 SDF 时序报告显示：在 **100 MHz（10 ns）时钟**下，setup slack 为 **1.631 ns**，setup/hold 均无违例。原始报告见 [`impl_1_util.rpt`](fft64_sim/reports/impl_1_util.rpt)、[`impl_1_timing.rpt`](fft64_sim/reports/impl_1_timing.rpt) 和 [`fft64_dit_sdf_timing_summary_routed.rpt`](fft64_sim/vivado_project/FFT64_SIM/FFT64_SIM.runs/impl_1/fft64_dit_sdf_timing_summary_routed.rpt)。

这些数字仅代表仓库中保存的这一版构建结果；器件、Vivado 版本、约束、综合选项和 I/O 分配都会影响最终结果。

## 设计说明与已知限制

- 当前 XDC 只创建了 10 ns 时钟，没有设置外部输入/输出延迟，因此上述 slack 是内部时钟到时钟结果。
- 实现报告包含默认 I/O 标准和未分配引脚位置的 Vivado 警告。生成 bitstream 前请补充与目标开发板对应的 XDC。
- `run_fft64_all.py` 内写死了 Windows Vivado 路径（`C:\\Xilinx\\Vivado\\2018.3\\bin\\vivado.bat`），其他系统请修改 `VIVADO_EXE` 或分别执行 TCL/Python 步骤。
- Vivado/XSim 生成物有意保留以便审计；清理后重新构建可能会在 `vivado_project/` 和 `logs/` 下产生更多文件。

## 背景资料

架构参考 Keshab K. Parhi 的 *VLSI Digital Signal Processing Systems: Design and Implementation* 中的折叠和 SDF 思路。NumPy 用作浮点参考，Vivado XSim 用于 RTL 仿真和实现报告生成。

## License

当前仓库尚未包含 license 文件。如果要按特定许可证分发 RTL 或报告，请先补充对应许可证。
