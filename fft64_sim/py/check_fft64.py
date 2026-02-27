# -*- coding: utf-8 -*-
"""
Check Vivado 64-point FFT output against NumPy reference, and plot/save spectra.

输入模式与 SystemVerilog testbench 保持一致：
0: 冲激  1: 正弦  2: 方波  3: 随机 LCG  4: 从 rt1/input.txt 读取
"""

import argparse
import os
from typing import Tuple

import matplotlib.pyplot as plt
import numpy as np

# 工程根目录：fft64_sim
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PLOT_DIR = os.path.join(ROOT, "plots")

# Vivado XSim 输出目录（output_vivado.txt 所在处）
XSIM_DIR = os.path.join(
    ROOT,
    "vivado_project",
    "FFT64_SIM",
    "FFT64_SIM.sim",
    "sim_1",
    "behav",
    "xsim",
)

# 配置参数（需与 Verilog 一致）
N_POINTS = 64
DATA_WIDTH = 16
FRAC_BITS = 15  # Q1.15
INPUT_MODE = 1  # 默认模式为SINE，可用命令行覆盖
WAVE_K = 1  # 正弦/方波周期
AMP = 1 << (DATA_WIDTH - 3)  # 与 tb_fft64.sv 中 AMP 定义一致

INPUT_FILE = os.path.join(ROOT, "rt1", "input.txt")
OUTPUT_FILE = os.path.join(XSIM_DIR, "output_vivado.txt")


# =======================
# 定点 <-> 浮点
# =======================
def float_to_fixed(x: np.ndarray, frac_bits: int = FRAC_BITS) -> np.ndarray:
    return np.round(x * (1 << frac_bits)).astype(np.int16)


def fixed_to_float(x: np.ndarray, frac_bits: int = FRAC_BITS) -> np.ndarray:
    return x.astype(np.float64) / (1 << frac_bits)


# =======================
# 输入信号生成（与 SV 对齐）
# =======================
def my_rand(state: int) -> int:
    return (1664525 * state + 1013904223) & 0xFFFFFFFF


def gen_pulse() -> np.ndarray:
    real = np.zeros(N_POINTS, dtype=np.float64)
    imag = np.zeros(N_POINTS, dtype=np.float64)
    real[0] = AMP / (1 << FRAC_BITS)
    return real + 1j * imag


def gen_sine() -> np.ndarray:
    n = np.arange(N_POINTS)
    ang = 2.0 * np.pi * WAVE_K * n / N_POINTS
    real = np.sin(ang) * (AMP / (1 << FRAC_BITS))
    imag = np.zeros_like(real)
    return real + 1j * imag


def gen_square() -> np.ndarray:
    n = np.arange(N_POINTS)
    ang = 2.0 * np.pi * WAVE_K * n / N_POINTS
    s = np.sin(ang)
    real = np.where(s >= 0.0, AMP / (1 << FRAC_BITS), -AMP / (1 << FRAC_BITS))
    imag = np.zeros_like(real)
    return real + 1j * imag


def gen_random() -> np.ndarray:
    state = 0x12345678
    real_q = np.zeros(N_POINTS, dtype=np.int16)
    imag_q = np.zeros(N_POINTS, dtype=np.int16)
    for i in range(N_POINTS):
        state = my_rand(state)
        real_q[i] = np.int16(state & 0xFFFF)
        state = my_rand(state)
        imag_q[i] = np.int16(state & 0xFFFF)
    real = fixed_to_float(real_q)
    imag = fixed_to_float(imag_q)
    return real + 1j * imag


def gen_from_file(filename: str = INPUT_FILE) -> np.ndarray:
    if not os.path.exists(filename):
        raise FileNotFoundError(f"Cannot find input file: {filename}")
    real_list = []
    imag_list = []
    with open(filename, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            r_str, im_str = line.split()
            real_list.append(int(r_str))
            imag_list.append(int(im_str))
    if len(real_list) != N_POINTS:
        raise ValueError(f"Input length mismatch: got {len(real_list)}, expected {N_POINTS}")
    real = fixed_to_float(np.array(real_list, dtype=np.int16))
    imag = fixed_to_float(np.array(imag_list, dtype=np.int16))
    return real + 1j * imag


def gen_input_signal(mode: int) -> np.ndarray:
    print(f"[INFO] INPUT_MODE = {mode}")
    if mode == 0:
        return gen_pulse()
    if mode == 1:
        return gen_sine()
    if mode == 2:
        return gen_square()
    if mode == 3:
        return gen_random()
    if mode == 4:
        return gen_from_file()
    raise ValueError(f"Invalid INPUT_MODE = {mode}")


# =======================
# Vivado 输出读取
# =======================
def read_vivado_output(filename: str = OUTPUT_FILE) -> np.ndarray:
    if not os.path.exists(filename):
        raise FileNotFoundError(f"Cannot find Vivado output file: {filename}")
    real_list = []
    imag_list = []
    with open(filename, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            r_str, im_str = line.split()
            real_list.append(int(r_str))
            imag_list.append(int(im_str))
    if len(real_list) != N_POINTS:
        raise ValueError(f"Output length mismatch: got {len(real_list)}, expected {N_POINTS}")
    real = fixed_to_float(np.array(real_list, dtype=np.int16))
    imag = fixed_to_float(np.array(imag_list, dtype=np.int16))
    return real + 1j * imag


# =======================
# 绘图
# =======================
def plot_spectra(
    y_vivado: np.ndarray,
    y_ref: np.ndarray,
    save_dir: str,
    prefix: str = "fft_",
    show: bool = True,
):
    k = np.arange(N_POINTS)
    mag_vivado = np.abs(y_vivado)
    mag_ref = np.abs(y_ref)
    phase_vivado = np.angle(y_vivado)
    phase_ref = np.angle(y_ref)

    os.makedirs(save_dir, exist_ok=True)

    plt.figure()
    plt.stem(k, mag_vivado, linefmt="-", markerfmt="o", basefmt=" ")
    plt.stem(k, mag_ref, linefmt="--", markerfmt="x", basefmt=" ")
    plt.xlabel("k")
    plt.ylabel("|X[k]|")
    plt.title("Amplitude Spectrum Comparison")
    plt.legend(["Vivado", "Numpy"])
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(os.path.join(save_dir, f"{prefix}mag_compare.png"), dpi=200, bbox_inches="tight")

    plt.figure()
    plt.stem(k, phase_vivado, linefmt="-", markerfmt="o", basefmt=" ")
    plt.stem(k, phase_ref, linefmt="--", markerfmt="x", basefmt=" ")
    plt.xlabel("k")
    plt.ylabel("Phase (rad)")
    plt.title("Phase Spectrum Comparison")
    plt.legend(["Vivado", "Numpy"])
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(os.path.join(save_dir, f"{prefix}phase_compare.png"), dpi=200, bbox_inches="tight")

    if show:
        plt.show()
    else:
        plt.close("all")


def threshold_complex(arr: np.ndarray, thr: float = 1e-6) -> np.ndarray:
    real = np.where(np.abs(arr.real) < thr, 0.0, arr.real)
    imag = np.where(np.abs(arr.imag) < thr, 0.0, arr.imag)
    return real + 1j * imag


# =======================
# 参数与主流程
# =======================
def parse_args():
    parser = argparse.ArgumentParser(description="Check 64-point FFT (Vivado vs NumPy)")
    parser.add_argument("--input-mode", type=int, choices=range(5), default=INPUT_MODE,
                        help="0:pulse 1:sine 2:square 3:random 4:from_file")
    parser.add_argument("--save-dir", type=str, default=None,
                        help="directory to save plots (default: plots/)")
    parser.add_argument("--prefix", type=str, default=None,
                        help="filename prefix for saved plots (default: fft_ or modeX label when save-dir is set)")
    parser.add_argument("--no-show", action="store_true",
                        help="do not display plots (batch mode)")
    return parser.parse_args()


def main():
    args = parse_args()

    mode_labels = {
        0: "mode0_pulse_",
        1: "mode1_sine_",
        2: "mode2_square_",
        3: "mode3_random_",
        4: "mode4_fromfile_",
    }

    input_mode = args.input_mode
    save_dir = args.save_dir or DEFAULT_PLOT_DIR
    prefix = args.prefix
    if prefix is None:
        prefix = mode_labels.get(input_mode, "fft_") if args.save_dir else "fft_"

    show = not args.no_show

    x = gen_input_signal(input_mode)
    y_ref = np.fft.fft(x) / N_POINTS
    y_ref = threshold_complex(y_ref)

    y_vivado = read_vivado_output()

    diff = y_vivado - y_ref
    abs_err = np.abs(diff)

    print("=======================================")
    print(" FFT 64-point Check Result")
    print("=======================================")
    print(f"Max abs error : {np.max(abs_err):.6e}")
    print(f"Mean abs error: {np.mean(abs_err):.6e}")

    print("\nFirst 64 points comparison:")
    print(" idx |  Vivado (real, imag) |   Ref (real, imag)   |    Diff (real, imag)")
    print("-----+----------------------+----------------------+------------------------")
    for i in range(min(64, N_POINTS)):
        vr = y_vivado.real[i]
        vi = y_vivado.imag[i]
        rr = y_ref.real[i]
        ri = y_ref.imag[i]
        dr = diff.real[i]
        di = diff.imag[i]
        print(f"{i:4d} | {vr:+.6f}, {vi:+.6f} | {rr:+.6f}, {ri:+.6f} | {dr:+.2e}, {di:+.2e}")

    plot_spectra(y_vivado, y_ref, save_dir=save_dir, prefix=prefix, show=show)


if __name__ == "__main__":
    main()
