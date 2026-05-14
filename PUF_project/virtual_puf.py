"""
virtual_puf.py
--------------
Virtual Ring Oscillator PUF model for HIL (Hardware-in-the-Loop) simulation.
Mimics the behavior of a real RO-PUF on a Zybo Z7 FPGA.

Architecture:
  - N_RO ring oscillators, each with a stable "silicon offset" (frequency bias)
    drawn from a Gaussian distribution at initialization (models manufacturing variation)
  - A challenge selects an (i, j) oscillator pair; response bit = 1 if count(ROi) > count(ROj)
  - Noise (Gaussian jitter) is injected per measurement to model thermal/environmental BER
  - Trojan mode: forces a subset of ROs to stuck-at or adds delay to flip responses

Author: Generated for Rahul Biju – Rutgers HW Security Project
"""

import numpy as np
import csv
import json
from pathlib import Path
from dataclasses import dataclass, field, asdict
from typing import Optional


# ─── Configuration ───────────────────────────────────────────────────────────

@dataclass
class PUFConfig:
    n_ros: int = 128            # Number of ring oscillators (pairs cover 64 challenges)
    n_challenges: int = 64      # Number of challenge indices
    base_freq_mhz: float = 200.0   # Nominal RO frequency (MHz)
    offset_std_pct: float = 0.5    # Silicon offset std dev as % of base freq
    noise_std_pct: float = 0.1     # Thermal noise std dev as % of base freq
    window_cycles: int = 1000      # Measurement window in cycles
    majority_vote_n: int = 9       # Majority vote repetitions (must be odd)
    auth_threshold: float = 0.90   # Match rate to PASS authentication
    trojan_fraction: float = 0.25  # Fraction of ROs affected by Trojan
    trojan_delay_pct: float = 1.5  # Delay added to trojan ROs (% of base freq)
    random_seed: Optional[int] = 42


# ─── Virtual RO-PUF Core ─────────────────────────────────────────────────────

class VirtualROPUF:
    """
    Models a Ring Oscillator PUF with:
      - Per-oscillator silicon frequency offsets (fixed at init, models manufacturing)
      - Per-measurement Gaussian noise (models thermal/environmental variation)
      - Optional Trojan mode (stuck-at delay on a subset of oscillators)
    """

    def __init__(self, config: PUFConfig = PUFConfig()):
        self.cfg = config
        rng = np.random.default_rng(config.random_seed)

        # Silicon offsets: stable per-device, drawn once
        offset_std = config.base_freq_mhz * (config.offset_std_pct / 100.0)
        self.silicon_offsets = rng.normal(0, offset_std, size=config.n_ros)

        # Trojan state
        self._trojan_active = False
        self._trojan_ros = rng.choice(
            config.n_ros,
            size=int(config.n_ros * config.trojan_fraction),
            replace=False
        )

        self._rng = rng
        self._noise_std = config.base_freq_mhz * (config.noise_std_pct / 100.0)

    # ── Challenge → RO index mapping ─────────────────────────────────────────
    def _challenge_to_pair(self, challenge: int) -> tuple[int, int]:
        """Map a challenge index to an (i, j) RO pair."""
        i = (challenge * 2) % self.cfg.n_ros
        j = (challenge * 2 + 1) % self.cfg.n_ros
        return i, j

    # ── Single raw count measurement ─────────────────────────────────────────
    def _measure_count(self, ro_idx: int) -> float:
        """Return the oscillation count for one RO over the measurement window."""
        freq = self.cfg.base_freq_mhz + self.silicon_offsets[ro_idx]

        # Apply Trojan delay (reduces effective frequency)
        if self._trojan_active and ro_idx in self._trojan_ros:
            delay = self.cfg.base_freq_mhz * (self.cfg.trojan_delay_pct / 100.0)
            freq -= delay

        # Add thermal noise
        freq += self._rng.normal(0, self._noise_std)

        # Count = freq * window (normalized; relative comparison is what matters)
        count = freq * self.cfg.window_cycles
        return max(count, 0.0)

    # ── Single response bit (with majority voting) ────────────────────────────
    def get_response_bit(self, challenge: int) -> int:
        """
        Returns a single stabilized response bit for a given challenge.
        Uses majority voting over cfg.majority_vote_n measurements.
        """
        i, j = self._challenge_to_pair(challenge)
        votes = []
        for _ in range(self.cfg.majority_vote_n):
            ci = self._measure_count(i)
            cj = self._measure_count(j)
            votes.append(1 if ci > cj else 0)
        return 1 if sum(votes) > self.cfg.majority_vote_n // 2 else 0

    # ── Full response vector ──────────────────────────────────────────────────
    def get_response_vector(self, challenges: list[int]) -> list[int]:
        """Returns response bits for a list of challenges."""
        return [self.get_response_bit(c) for c in challenges]

    # ── Trojan control ────────────────────────────────────────────────────────
    def enable_trojan(self):
        self._trojan_active = True

    def disable_trojan(self):
        self._trojan_active = False

    @property
    def trojan_active(self) -> bool:
        return self._trojan_active


# ─── Verifier (Raspberry Pi model) ───────────────────────────────────────────

@dataclass
class EnrollmentRecord:
    challenges: list[int]
    golden_crps: list[int]   # golden challenge-response pairs


class Verifier:
    """
    Models the Raspberry Pi verifier.
    Handles enrollment, authentication, and result logging.
    """

    def __init__(self, config: PUFConfig = PUFConfig()):
        self.cfg = config
        self._enrollment: Optional[EnrollmentRecord] = None

    @property
    def is_enrolled(self) -> bool:
        return self._enrollment is not None

    # ── Enrollment ────────────────────────────────────────────────────────────
    def enroll(self, puf: VirtualROPUF) -> EnrollmentRecord:
        """
        Query the PUF for all challenges and store golden CRPs.
        """
        challenges = list(range(self.cfg.n_challenges))
        responses = puf.get_response_vector(challenges)
        self._enrollment = EnrollmentRecord(challenges=challenges, golden_crps=responses)
        print(f"[Verifier] Enrollment complete — {len(challenges)} CRPs stored.")
        return self._enrollment

    # ── Authentication ────────────────────────────────────────────────────────
    def authenticate(self, puf: VirtualROPUF) -> dict:
        """
        Re-query the PUF and compare against golden CRPs.
        Returns a result dict with match_rate, BER, pass/fail, and per-bit details.
        """
        if not self.is_enrolled:
            raise RuntimeError("Verifier not enrolled. Call enroll() first.")

        challenges = self._enrollment.challenges
        live_responses = puf.get_response_vector(challenges)
        golden = self._enrollment.golden_crps

        mismatches = [g != l for g, l in zip(golden, live_responses)]
        ber = sum(mismatches) / len(mismatches)
        match_rate = 1.0 - ber
        passed = match_rate >= self.cfg.auth_threshold

        result = {
            "n_challenges": len(challenges),
            "match_rate": round(match_rate, 4),
            "ber": round(ber, 4),
            "mismatched_bits": int(sum(mismatches)),
            "passed": passed,
            "trojan_detected": ber > (1 - self.cfg.auth_threshold),
            "golden": golden,
            "live": live_responses,
            "mismatch_mask": [int(m) for m in mismatches],
        }
        return result


# ─── Metrics ─────────────────────────────────────────────────────────────────

def hamming_distance(a: list[int], b: list[int]) -> int:
    return sum(x != y for x, y in zip(a, b))

def intra_device_hd(puf: VirtualROPUF, n_trials: int = 20) -> dict:
    """
    Measures intra-device Hamming Distance (reliability).
    Collects n_trials response vectors for the same challenges and computes
    average HD between each trial and the first (reference) trial.
    """
    challenges = list(range(puf.cfg.n_challenges))
    reference = puf.get_response_vector(challenges)
    hds = []
    for _ in range(n_trials - 1):
        trial = puf.get_response_vector(challenges)
        hds.append(hamming_distance(reference, trial))

    avg_hd = np.mean(hds)
    avg_ber = avg_hd / len(challenges)
    return {
        "n_trials": n_trials,
        "avg_intra_hd": round(float(avg_hd), 4),
        "avg_ber": round(float(avg_ber), 4),
        "min_hd": int(min(hds)),
        "max_hd": int(max(hds)),
    }

def inter_device_hd(puf_a: VirtualROPUF, puf_b: VirtualROPUF) -> dict:
    """
    Measures inter-device Hamming Distance (uniqueness) between two PUF instances.
    Ideal value: ~50% of n_challenges (responses are uncorrelated between devices).
    """
    challenges = list(range(puf_a.cfg.n_challenges))
    resp_a = puf_a.get_response_vector(challenges)
    resp_b = puf_b.get_response_vector(challenges)
    hd = hamming_distance(resp_a, resp_b)
    return {
        "inter_hd": hd,
        "inter_hd_pct": round(hd / len(challenges) * 100, 2),
        "ideal_pct": 50.0,
    }


# ─── CSV Logger ──────────────────────────────────────────────────────────────

class DataLogger:
    """Logs authentication results and metrics to CSV files."""

    def __init__(self, output_dir: str = "."):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def log_auth_result(self, result: dict, label: str = "normal", filename: str = "auth_log.csv"):
        path = self.output_dir / filename
        write_header = not path.exists()
        with open(path, "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["label", "match_rate", "ber", "mismatched_bits", "passed", "trojan_detected"])
            if write_header:
                writer.writeheader()
            writer.writerow({
                "label": label,
                "match_rate": result["match_rate"],
                "ber": result["ber"],
                "mismatched_bits": result["mismatched_bits"],
                "passed": result["passed"],
                "trojan_detected": result["trojan_detected"],
            })
        print(f"[Logger] Saved auth result to {path}")

    def log_metrics(self, metrics: dict, filename: str = "metrics_log.csv"):
        path = self.output_dir / filename
        write_header = not path.exists()
        with open(path, "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=metrics.keys())
            if write_header:
                writer.writeheader()
            writer.writerow(metrics)
        print(f"[Logger] Saved metrics to {path}")
