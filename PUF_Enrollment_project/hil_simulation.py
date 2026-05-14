"""
hil_simulation.py
-----------------
Hardware-in-the-Loop (HIL) simulation runner.

Runs the full attestation protocol end-to-end:
  1. Enrollment   — Verifier queries virtual PUF and stores golden CRPs
  2. Authentication — Normal mode (should PASS)
  3. Stress test  — Multiple auth trials to measure BER stability
  4. Trojan mode  — Inject fault and show anomaly detection (should FAIL)
  5. Metrics      — Intra-device and inter-device Hamming Distance

All results are printed to console and saved as CSVs in ./hil_output/

Usage:
    python hil_simulation.py

    # Or with custom noise level:
    python hil_simulation.py --noise 0.3

    # Sweep noise levels (BER characterization):
    python hil_simulation.py --sweep
"""

import argparse
import json
import numpy as np
from virtual_puf import VirtualROPUF, Verifier, DataLogger, PUFConfig
from virtual_puf import intra_device_hd, inter_device_hd


BANNER = """
╔══════════════════════════════════════════════════════╗
║   PUF-Based Edge Device Attestation — HIL Simulator  ║
║   Rutgers Hardware & System Security                 ║
╚══════════════════════════════════════════════════════╝
"""

def print_section(title: str):
    print(f"\n{'─'*54}")
    print(f"  {title}")
    print(f"{'─'*54}")

def print_auth_result(result: dict, label: str):
    status = "✅ PASS" if result["passed"] else "❌ FAIL"
    trojan = "⚠️  TROJAN DETECTED" if result["trojan_detected"] else ""
    print(f"  [{label}]  Match Rate: {result['match_rate']*100:.1f}%  |  BER: {result['ber']*100:.2f}%  |  {status}  {trojan}")


def run_enrollment_and_auth(cfg: PUFConfig, logger: DataLogger, noise_pct: float = None):
    if noise_pct is not None:
        cfg.noise_std_pct = noise_pct

    puf = VirtualROPUF(cfg)
    verifier = Verifier(cfg)

    # ── 1. Enrollment ──────────────────────────────────────────────────────
    print_section("PHASE 1 — Enrollment")
    record = verifier.enroll(puf)
    ones = sum(record.golden_crps)
    zeros = cfg.n_challenges - ones
    print(f"  Golden CRPs: {cfg.n_challenges} bits  |  1s: {ones}  0s: {zeros}  (ideal ~50/50)")

    # ── 2. Normal Authentication ───────────────────────────────────────────
    print_section("PHASE 2 — Authentication (Normal Mode)")
    result_normal = verifier.authenticate(puf)
    print_auth_result(result_normal, "Normal")
    logger.log_auth_result(result_normal, label="normal")

    # ── 3. Stress Test (N repeated auths) ─────────────────────────────────
    print_section("PHASE 3 — Stress Test (20 authentication trials)")
    pass_count = 0
    bers = []
    for trial in range(20):
        r = verifier.authenticate(puf)
        bers.append(r["ber"])
        if r["passed"]:
            pass_count += 1
        logger.log_auth_result(r, label=f"stress_{trial}")

    print(f"  Pass rate: {pass_count}/20  |  Avg BER: {np.mean(bers)*100:.3f}%  |  Max BER: {np.max(bers)*100:.3f}%")

    # ── 4. Trojan / Fault Injection ────────────────────────────────────────
    print_section("PHASE 4 — Trojan / Fault Injection Mode")
    puf.enable_trojan()
    result_trojan = verifier.authenticate(puf)
    print_auth_result(result_trojan, "Trojan")
    logger.log_auth_result(result_trojan, label="trojan")
    puf.disable_trojan()

    # ── 5. Intra-device HD (Reliability) ──────────────────────────────────
    print_section("PHASE 5 — Intra-Device Hamming Distance (Reliability)")
    intra = intra_device_hd(puf, n_trials=20)
    print(f"  Avg intra-HD: {intra['avg_intra_hd']:.2f} bits / {cfg.n_challenges}  |  Avg BER: {intra['avg_ber']*100:.3f}%")
    print(f"  Min HD: {intra['min_hd']}  |  Max HD: {intra['max_hd']}")
    logger.log_metrics({**intra, "noise_pct": cfg.noise_std_pct}, filename="intra_hd_log.csv")

    # ── 6. Inter-device HD (Uniqueness) ───────────────────────────────────
    print_section("PHASE 6 — Inter-Device Hamming Distance (Uniqueness)")
    puf_b = VirtualROPUF(PUFConfig(random_seed=99))  # "Different device"
    inter = inter_device_hd(puf, puf_b)
    print(f"  Inter-HD: {inter['inter_hd']} bits ({inter['inter_hd_pct']}%)  |  Ideal: ~{inter['ideal_pct']}%")
    logger.log_metrics({**inter, "noise_pct": cfg.noise_std_pct}, filename="inter_hd_log.csv")

    return {
        "normal": result_normal,
        "trojan": result_trojan,
        "stress_avg_ber": float(np.mean(bers)),
        "intra": intra,
        "inter": inter,
    }


def run_noise_sweep(cfg: PUFConfig, logger: DataLogger):
    """
    Sweep noise_std_pct from 0.0 to 1.5% and measure how BER grows.
    Useful for calibrating majority_vote_n against your real Zybo dataset.
    """
    print_section("NOISE SWEEP — BER vs Noise Level")
    noise_levels = [round(x, 2) for x in np.arange(0.0, 1.6, 0.1)]
    print(f"  {'Noise %':>10}  {'Normal BER %':>14}  {'Trojan BER %':>14}  {'Result':>8}")
    print(f"  {'─'*10}  {'─'*14}  {'─'*14}  {'─'*8}")

    for noise in noise_levels:
        sweep_cfg = PUFConfig(noise_std_pct=noise, random_seed=42)
        puf = VirtualROPUF(sweep_cfg)
        verifier = Verifier(sweep_cfg)
        verifier.enroll(puf)

        r_normal = verifier.authenticate(puf)
        puf.enable_trojan()
        r_trojan = verifier.authenticate(puf)
        puf.disable_trojan()

        status = "PASS" if r_normal["passed"] else "FAIL"
        print(f"  {noise:>10.2f}  {r_normal['ber']*100:>13.3f}%  {r_trojan['ber']*100:>13.3f}%  {status:>8}")

        logger.log_metrics({
            "noise_pct": noise,
            "normal_ber": r_normal["ber"],
            "trojan_ber": r_trojan["ber"],
            "normal_match_rate": r_normal["match_rate"],
            "passed": r_normal["passed"],
        }, filename="noise_sweep_log.csv")


def main():
    parser = argparse.ArgumentParser(description="PUF HIL Simulator")
    parser.add_argument("--noise", type=float, default=0.1,
                        help="Noise std dev as %% of base freq (default: 0.1)")
    parser.add_argument("--sweep", action="store_true",
                        help="Run noise sweep instead of single simulation")
    args = parser.parse_args()

    print(BANNER)
    cfg = PUFConfig(noise_std_pct=args.noise)
    logger = DataLogger(output_dir="./hil_output")

    print(f"  Config: {cfg.n_challenges} challenges | {cfg.n_ros} ROs | "
          f"noise={cfg.noise_std_pct}% | majority_vote_n={cfg.majority_vote_n} | "
          f"auth_threshold={cfg.auth_threshold*100:.0f}%")

    if args.sweep:
        run_noise_sweep(cfg, logger)
    else:
        results = run_enrollment_and_auth(cfg, logger, noise_pct=args.noise)

        print_section("SUMMARY")
        print(f"  Normal auth:    {'PASS ✅' if results['normal']['passed'] else 'FAIL ❌'}  "
              f"(Match: {results['normal']['match_rate']*100:.1f}%  BER: {results['normal']['ber']*100:.2f}%)")
        print(f"  Trojan auth:    {'PASS ✅' if results['trojan']['passed'] else 'FAIL ❌'}  "
              f"(Match: {results['trojan']['match_rate']*100:.1f}%  BER: {results['trojan']['ber']*100:.2f}%)")
        print(f"  Stress avg BER: {results['stress_avg_ber']*100:.3f}%")
        print(f"  Intra HD (reliability): {results['intra']['avg_ber']*100:.3f}% avg BER")
        print(f"  Inter HD (uniqueness):  {results['inter']['inter_hd_pct']}% (ideal ~50%)")
        print(f"\n  📁 All logs saved to: ./hil_output/\n")


if __name__ == "__main__":
    main()
