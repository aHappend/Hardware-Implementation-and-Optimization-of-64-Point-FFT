# FFT64 Simulation & Verification

## 项目亮点
- 64 点 radix-2 DIT FFT（SDF 结构），含旋转因子 ROM、复乘器、输入位反转缓冲以及级联延迟线。
- RTL、testbench 与 Python 校验脚本统一使用 Q1.15 定点接口，内部计算保留额外位宽后再量化。
- 五种激励模式（脉冲/正弦/方波/随机/文件输入）在 SystemVerilog 与 Python 之间完全对齐，便于逐点比对。
- `run_fft64_all.py` 一键完成 Vivado 批处理仿真、NumPy 校验，并按时间戳归档 Vivado 日志。
- `py/check_fft64.py` 打印最大/平均误差、列出逐点对比，并保存幅度/相位叠加图。

## 仓库结构
```
fft64_sim/
├─ sim/                    # SystemVerilog RTL 与 testbench，实际使用的是`sim/fft64_model.sv`和`sim/tb_fft64.sv`，其余为全并行和折叠版的原码，可用来替换使用
├─ py/                     # Python 校验与绘图脚本
├─ scripts/                # Vivado 批处理 TCL
├─ vivado_project/         # Vivado 工程与 XSim 产物，FFT64_SIM.xpr也在此处
├─ rt1/                    # 可选外部激励 (input.txt)
├─ plots/ / plots_example/ # 已生成 / 示例图
├─ logs/                   # 运行日志（按时间戳归档）
├─ run_fft64_all.py        # 一键驱动脚本
└─ README.md               # 说明，本文件（含英文 + 中文）
```

## 核心源码
- `sim/fft64_model.sv`：FFT 数据通路，包含所有阶段控制与乘加逻辑。
- `sim/tb_fft64.sv`：自驱动 testbench，输出 `output_vivado.txt`。
- `scripts/run_sim.tcl`：Vivado XSim 批处理脚本。
- `py/check_fft64.py`：NumPy 参考实现 + 绘图。
- `rt1/input.txt`：当输入模式设为 FILE 时读取的 64 行定点样本。

## 架构概述
一帧 64 点数据依次穿过 6 个 DIT SDF 级（延迟长度为 `1 << stage_id`）。旋转因子由 ROM 提供，复乘单元输出蝶形的加/减结果。归一化与 Python 保持一致：$Y[k] = \frac{1}{64} \sum_{n=0}^{63} x[n] e^{-j 2 \pi k n / 64}$。

## 仿真流程
1. **激励准备**：`tb_fft64.sv` 根据 `INPUT_MODE` 生成 64 点输入，默认幅度 `2^(DATA_WIDTH-3)`。
2. **Vivado 运行**：执行 `vivado -mode batch -source scripts/run_sim.tcl`（或 Python 封装脚本），生成 `output_vivado.txt`。
3. **Python 校验**：`py/check_fft64.py` 用相同模式构造输入，运行 `numpy.fft.fft(x)/64`，打印误差并绘图。
4. **日志归档**：`run_fft64_all.py` 将新的 `vivado.log/jou/backup` 移动至 `logs/vivado_run_时间戳/`，并可选复制 XSim 日志。

## 输入模式（SV 与 Python 共享）
| ID | 模式      | 说明 |
|----|-----------|------|
| 0  | PULSE     | 仅 `x[0]=AMP`，其余为 0，用于冲激响应 |
| 1  | SINE      | 单频正弦，频率索引由 `WAVE_K` 决定 |
| 2  | SQUARE    | 正弦符号化得到的方波 |
| 3  | RANDOM    | LCG 生成的复数序列，SV/Python 完全同步 |
| 4  | FROM_FILE | 读取 `rt1/input.txt` 的 64 行 `real imag` |

请保持 `sim/tb_fft64.sv` 与 `py/check_fft64.py` 中的 `INPUT_MODE` 一致（或在命令行通过 `--input-mode` 覆盖）。

## 使用方法
**环境要求**
- Vivado 2018.3（若安装路径不同，请修改 `run_fft64_all.py` 中的 `VIVADO_EXE`）。
- Python 3.8+，并安装 `numpy`、`matplotlib`。

**一键运行 Vivado + Python**
```
python run_fft64_all.py
```

**单独运行 Vivado**
```
vivado -mode batch -source scripts/run_sim.tcl
```

**单独运行 Python 校验**
```
python py/check_fft64.py --input-mode 1 --no-show --save-dir plots
```

## 输出与日志
- FFT 结果：`output_vivado.txt`（64 行 `real imag`，Q1.15）。
- 绘图：`py/check_fft64.py` 默认在 `plots/` 下保存幅度/相位图。
- Vivado 日志：`run_fft64_all.py` 会在 `logs/` 下生成 `vivado_run_日期_时间/` 文件夹。

## Python 校验脚本要点
- 与 testbench 共享激励发生器、位宽与幅度设置。
- 内置定点/浮点互转函数，便于调试。
- 打印最大/平均绝对误差、逐点差值，并提供 `threshold_complex()` 清理接近零的噪声。

## 常见问题
- **Vivado 可执行文件不存在**：确认安装路径，更新 `VIVADO_EXE`。
- **缺少 `output_vivado.txt`**：确保仿真已成功完成或路径正确。
- **相位图杂散较多**：幅度接近零的频点相位会发散，可忽略或启用阈值函数。
- **自定义激励**：把 64 行 `real imag` 写入 `rt1/input.txt` 并设定 `INPUT_MODE=4`。
