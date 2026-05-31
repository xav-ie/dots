# Per-process CPU accounting. `process-logger` samples cumulative CPU time on a
# timer and records per-interval deltas to SQLite; run `process-top` to see what
# used the most CPU over a recent window — something btop/top cannot answer.
{ pkgs, ... }:
{
  home.packages = [ pkgs.pkgs-mine.process-logger ];

  # Sample every 10 minutes. Shorter intervals catch more short-lived
  # processes; longer ones only lose coverage (the snapshot-diff is accurate
  # for any process alive at sample time regardless of interval).
  services.scheduled.process-logger = {
    description = "Sample per-process CPU usage into SQLite";
    command = "${pkgs.pkgs-mine.process-logger}/bin/process-logger";
    interval = 600;
  };
}
