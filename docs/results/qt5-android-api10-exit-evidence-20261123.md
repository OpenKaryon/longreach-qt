# Qt5 API10 x86: exit-evidence correction, 2026-11-23

The earlier sound-cache report recorded fourteen accepted cases under the
then-current collector. That result and its original JSON remain historical
records. The interpretation that the full batch and two focused repeats proved
clean extended-selftest shutdown is superseded by this evidence review.

The preserved extended-selftest logs contain debuggerd crash evidence for the
application process alongside a zero native return marker. The old fatal-error
filter did not include that debuggerd format. A matching process-death message
does not establish whether termination was clean. The detailed logs and
integrity records remain in the private lab; they are not copied here.

This does not establish the crash's cause or prove which change would fix it.
The sound-cache patch still needs controlled teardown verification. No new
guest run, SDK rebuild or emulator change was performed for this review.

The current follow-up requires a scoped launch marker, one matching start/death
PID pair, two subsequent observations showing the application absent from ps,
and no captured fatal, debuggerd or forced-termination evidence. Collectors
recheck the recorded log/ps hashes rather than trusting the return-zero file.
This is observation of termination, not a captured operating-system exit code.
Qt4's resident JNI Activity and the standalone runtime JNI probe have a
different lifecycle and are not labeled natural-exit tests.

These source changes are covered by ordinary fixtures. A new actual clean
qualification requires a separately authorized run with the strengthened gate.
