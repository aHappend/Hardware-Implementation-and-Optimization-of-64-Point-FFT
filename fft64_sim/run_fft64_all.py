# run_fft64_all.py
# 一键运行：Vivado 仿真 + Python 校验
# 额外功能：把根目录的 vivado log/jou/backup 收纳到 logs/ 目录里

import os
import sys
import subprocess
import glob
import shutil
from datetime import datetime


def collect_logs(root_dir: str):
    """
    收集本次 Vivado 运行产生的日志文件，统一放到 logs/vivado_run_xxx/ 目录。
    - 移动根目录下的 vivado.log / vivado.jou / vivado_*.backup.*
    - 复制 xsim 目录中的 webtalk / simulate.log / *.backup.* / *.jou
    """
    logs_root = os.path.join(root_dir, "logs")
    os.makedirs(logs_root, exist_ok=True)

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    this_run = os.path.join(logs_root, f"vivado_run_{stamp}")
    os.makedirs(this_run, exist_ok=True)

    print(f"[INFO] 收集 Vivado 日志到目录: {this_run}")

    # 1) 根目录下的 vivado 日志文件：移动过去
    root_patterns = [
        "vivado.log",
        "vivado.jou",
        "vivado_*.backup.log",
        "vivado_*.backup.jou",
    ]
    for pat in root_patterns:
        for f in glob.glob(os.path.join(root_dir, pat)):
            try:
                shutil.move(f, os.path.join(this_run, os.path.basename(f)))
                print(f"  [MOVE] {f}")
            except Exception as e:
                print(f"  [WARN] 无法移动 {f}: {e}")
    
    # 2) xsim 目录中的日志：复制一份（不动原目录）
    xsim_dir = os.path.join(
        root_dir,
        "vivado_project", "FFT64_SIM", "FFT64_SIM.sim",
        "sim_1", "behav", "xsim"
    )
    if os.path.isdir(xsim_dir):
        xsim_patterns = [
            "simulate.log",
        ]
        for pat in xsim_patterns:
            for f in glob.glob(os.path.join(xsim_dir, pat)):
                try:
                    shutil.copy2(f, os.path.join(this_run, os.path.basename(f)))
                    print(f"  [COPY] {f}")
                except Exception as e:
                    print(f"  [WARN] 无法复制 {f}: {e}")
    else:
        print(f"[WARN] xsim 目录不存在: {xsim_dir}")
    


def main():
    # 工程根目录（fft64_sim）
    root_dir = os.path.dirname(os.path.abspath(__file__))

    #  Vivado 绝对路径
    VIVADO_EXE = r"C:\Xilinx\Vivado\2018.3\bin\vivado.bat"
    if not os.path.exists(VIVADO_EXE):
        print(f"[ERROR] Vivado 路径不存在：{VIVADO_EXE}")
        sys.exit(1)

    # ========== STEP 1: 调用 Vivado 运行仿真 ==========
    print("========== STEP 1: Run Vivado Simulation ==========")

    tcl_path = os.path.join(root_dir, "scripts", "run_sim.tcl")
    print(f"[INFO] Using TCL script: {tcl_path}")

    try:
        subprocess.run(
            [VIVADO_EXE, "-mode", "batch", "-source", tcl_path],
            check=True
        )
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Vivado 仿真失败，返回码 = {e.returncode}")
        sys.exit(e.returncode)

    print("[INFO] Vivado 仿真完成。")

    # 收纳本次运行的日志
    collect_logs(root_dir)

    # ========== STEP 2: 调用 Python 校验脚本 ==========
    print("\n========== STEP 2: Run Python check_fft64 ==========")

    py_script = os.path.join(root_dir, "py", "check_fft64.py")
    print(f"[INFO] Using Python script: {py_script}")

    try:
        subprocess.run(
            [sys.executable, py_script],
            check=True
        )
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] check_fft64.py 运行失败，返回码 = {e.returncode}")
        sys.exit(e.returncode)

    print("\n========== ALL DONE ==========")


if __name__ == "__main__":
    main()
