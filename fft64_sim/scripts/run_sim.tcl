# scripts/run_sim.tcl
# 从命令行运行 Vivado 行为仿真，生成 output_vivado.txt

# 打开工程（相对于当前启动目录：fft64_sim）
open_project ./vivado_project/FFT64_SIM/FFT64_SIM.xpr

# 使用默认仿真设置，启动行为仿真
launch_simulation -mode behavioral

# 注意：在 batch 模式下，launch_simulation 会跑到 $finish 自动结束，
# 不需要再 run all，否则会卡住脚本。

# 退出 Vivado
quit
