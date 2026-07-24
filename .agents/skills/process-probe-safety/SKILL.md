---
name: process-probe-safety
description: Use when creating, changing, or running probes that spawn child processes, exercise parent-death or termination behavior, or drive macOS application UI.
---

# Process Probe Safety

A process probe is complete only at a **clean exit**: its assertions passed or
reported failure, every process it started was reaped, and no asynchronous crash
escaped the harness.

## 1. Establish the evidence baseline

Before launching the probe, identify every executable it may start and record:

- existing matching process IDs;
- the current macOS DiagnosticReports entries for those executables, when on
  macOS;
- the expected parent/child relationship and terminal exit status.

Completion criterion: a later check can distinguish processes and crash
artifacts created by this probe from pre-existing ones.

## 2. Make cleanup structural

Track every spawned process as soon as its PID exists. Route success, assertion
failure, timeout, and thrown errors through one cleanup path. That path:

1. closes owned pipes;
2. requests graceful termination when appropriate;
3. applies bounded forceful termination when needed;
4. waits for every child to exit before the harness returns.

In Swift, report failures by throwing or returning through cleanup. Call
`exit`, `_exit`, `fatalError`, or `preconditionFailure` only after owned
processes have been reaped because these paths bypass `defer`.

Completion criterion: every harness return path reaches the same bounded reaper.

## 3. Gate on asynchronous evidence

After each probe—including a failed assertion—check all of the following before
changing code or rerunning:

- no process started by the probe remains alive or reparented;
- each observed exit status matches the scenario;
- no new matching crash report appeared;
- stderr and relevant OS logs contain no unaccounted failure.

For macOS application probes, a visible window or passing UI assertion is
insufficient by itself. Cancel or submit the prompt, wait for the helper and
broker to exit, then apply the clean-exit checks.

Completion criterion: the probe has a clean exit, or the asynchronous failure is
the active diagnosis target.

## 4. Stop on leaked evidence

When a process remains, a crash report appears, or termination cannot be
observed, preserve that evidence and switch to diagnosis. Build a red-capable
loop for the process-lifecycle failure before making another product change.

Completion criterion: no iteration continues past an unexplained leak, crash,
or asynchronous termination.
