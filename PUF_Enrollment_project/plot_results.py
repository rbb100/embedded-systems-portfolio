"""
plot_results.py
---------------
Generates publication-ready plots from HIL simulation CSV outputs.

Plots produced:
  1. Auth log      — Match rate & BER across normal / stress / trojan runs
  2. Noise sweep   — BER vs noise level (normal vs trojan)
  3. Intra-HD      — Reliability bar chart
  4. Inter-HD      — Uniqueness gauge vs ideal 50%

Usage:
    python3 plot_results.py

Output: ./hil_output/plots/ (PNG files, 300 DPI)

Dependencies:
    pip install matplotlib pandas numpy
"""

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from pathlib import Path

# ─── Paths ───────────────────────────────────────────────────────────────────

INPUT_DIR  = Path("./hil_output")
OUTPUT_DIR = INPUT_DIR / "plots"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# ─── Style ───────────────────────────────────────────────────────────────────

COLORS = {
    "normal":  "#2563eb",
    "stress":  "#16a34a",
    "trojan":  "#dc2626",
    "threshold": "#f59e0b",
    "ideal":   "#7c3aed",
}

plt.rcParams.update({
    "font.family":    "monospace",
    "axes.spines.top":    False,
    "axes.spines.right":  False,
    "axes.grid":          True,
    "grid.alpha":         0.3,
    "grid.linestyle":     "--",
    "figure.dpi":         150,
})

def save(fig, name: str):
    path = OUTPUT_DIR / name
    fig.savefig(path, dpi=300, bbox_inches="tight")
    print(f"  ✅ Saved: {path}")
    plt.close(fig)


# ─── Plot 1 — Authentication Log ─────────────────────────────────────────────

def plot_auth_log():
    path = INPUT_DIR / "auth_log.csv"
    if not path.exists():
        print("  ⚠️  auth_log.csv not found, skipping.")
        return

    df = pd.read_csv(path)
    df["run"] = range(len(df))

    color_map = {"normal": COLORS["normal"], "trojan": COLORS["trojan"]}
    bar_colors = [color_map.get(str(l).split("_")[0], COLORS["stress"]) for l in df["label"]]

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 7), sharex=True)
    fig.suptitle("Authentication Runs — Match Rate & BER", fontsize=13, fontweight="bold")

    ax1.bar(df["run"], df["match_rate"] * 100, color=bar_colors, width=0.7, alpha=0.85)
    ax1.axhline(90, color=COLORS["threshold"], linewidth=1.5, linestyle="--", label="90% threshold")
    ax1.set_ylabel("Match Rate (%)")
    ax1.set_ylim(0, 105)
    ax1.legend(fontsize=9)

    ax2.bar(df["run"], df["ber"] * 100, color=bar_colors, width=0.7, alpha=0.85)
    ax2.axhline(10, color=COLORS["threshold"], linewidth=1.5, linestyle="--", label="10% BER limit")
    ax2.set_ylabel("BER (%)")
    ax2.set_xlabel("Run #")
    ax2.legend(fontsize=9)

    patches = [
        mpatches.Patch(color=COLORS["normal"],  label="Normal"),
        mpatches.Patch(color=COLORS["stress"],  label="Stress"),
        mpatches.Patch(color=COLORS["trojan"],  label="Trojan"),
    ]
    fig.legend(handles=patches, loc="upper right", fontsize=9, framealpha=0.8)
    fig.tight_layout()
    save(fig, "1_auth_log.png")


# ─── Plot 2 — Noise Sweep ────────────────────────────────────────────────────

def plot_noise_sweep():
    path = INPUT_DIR / "noise_sweep_log.csv"
    if not path.exists():
        print("  ⚠️  noise_sweep_log.csv not found. Run: python3 hil_simulation.py --sweep")
        return

    df = pd.read_csv(path)

    fig, ax = plt.subplots(figsize=(10, 5))
    fig.suptitle("BER vs Noise Level — Normal vs Trojan Mode", fontsize=13, fontweight="bold")

    ax.plot(df["noise_pct"], df["normal_ber"] * 100,
            color=COLORS["normal"], marker="o", linewidth=2, label="Normal mode BER")
    ax.plot(df["noise_pct"], df["trojan_ber"] * 100,
            color=COLORS["trojan"], marker="s", linewidth=2, linestyle="--", label="Trojan mode BER")
    ax.axhline(10, color=COLORS["threshold"], linewidth=1.5, linestyle=":", label="10% BER threshold")

    ax.axvspan(df["noise_pct"].min(), df[df["passed"] == True]["noise_pct"].max(),
               alpha=0.07, color=COLORS["normal"], label="PASS zone")

    ax.set_xlabel("Noise Std Dev (% of base freq)")
    ax.set_ylabel("BER (%)")
    ax.legend(fontsize=9)
    ax.set_ylim(0, 45)
    fig.tight_layout()
    save(fig, "2_noise_sweep.png")


# ─── Plot 3 — Intra-Device HD ────────────────────────────────────────────────

def plot_intra_hd():
    path = INPUT_DIR / "intra_hd_log.csv"
    if not path.exists():
        print("  ⚠️  intra_hd_log.csv not found, skipping.")
        return

    df = pd.read_csv(path)

    fig, ax = plt.subplots(figsize=(8, 4))
    fig.suptitle("Intra-Device Hamming Distance (Reliability)", fontsize=13, fontweight="bold")

    x = range(len(df))
    ax.bar(x, df["avg_intra_hd"], color=COLORS["normal"], alpha=0.8, label="Avg intra-HD")
    ax.errorbar(x,
                df["avg_intra_hd"],
                yerr=[df["avg_intra_hd"] - df["min_hd"],
                      df["max_hd"] - df["avg_intra_hd"]],
                fmt="none", color="black", capsize=5, linewidth=1.5, label="Min/Max range")

    ax.set_xticks(list(x))
    ax.set_xticklabels([f"noise={n:.2f}%" for n in df["noise_pct"]], rotation=15, fontsize=8)
    ax.set_ylabel("Hamming Distance (bits)")
    ax.set_xlabel("Configuration")
    ax.legend(fontsize=9)

    for i, row in df.iterrows():
        ax.text(i, row["avg_intra_hd"] + 0.15, f"BER\n{row['avg_ber']*100:.1f}%",
                ha="center", fontsize=7, color="#374151")

    fig.tight_layout()
    save(fig, "3_intra_hd.png")


# ─── Plot 4 — Inter-Device HD ────────────────────────────────────────────────

def plot_inter_hd():
    path = INPUT_DIR / "inter_hd_log.csv"
    if not path.exists():
        print("  ⚠️  inter_hd_log.csv not found, skipping.")
        return

    df = pd.read_csv(path)

    fig, ax = plt.subplots(figsize=(7, 4))
    fig.suptitle("Inter-Device Hamming Distance (Uniqueness)", fontsize=13, fontweight="bold")

    x = range(len(df))
    bars = ax.bar(x, df["inter_hd_pct"], color=COLORS["stress"], alpha=0.85, label="Inter-HD %")
    ax.axhline(50, color=COLORS["ideal"], linewidth=2, linestyle="--", label="Ideal 50%")

    ax.set_xticks(list(x))
    ax.set_xticklabels([f"noise={n:.2f}%" for n in df["noise_pct"]], rotation=15, fontsize=8)
    ax.set_ylabel("Inter-Device HD (%)")
    ax.set_ylim(0, 70)
    ax.legend(fontsize=9)

    for bar, val in zip(bars, df["inter_hd_pct"]):
        ax.text(bar.get_x() + bar.get_width() / 2,
                bar.get_height() + 1,
                f"{val:.1f}%", ha="center", fontsize=8, fontweight="bold")

    fig.tight_layout()
    save(fig, "4_inter_hd.png")


# ─── Main ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("\n📊 Generating plots from HIL simulation data...\n")
    plot_auth_log()
    plot_noise_sweep()
    plot_intra_hd()
    plot_inter_hd()
    print(f"\n✅ All plots saved to: {OUTPUT_DIR.resolve()}\n")
