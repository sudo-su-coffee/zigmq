# ZigMV Native 1.0.0-Beta Workstream

## Portability and builds

- [ ] Define supported Linux targets for x86_64, aarch64, and armv7 and add reproducible Zig build commands.
- [ ] Verify ReleaseSafe and ReleaseFast builds on the supported target matrix.
- [ ] Document Raspberry Pi deployment, system service limits, storage, and upgrade/rollback procedure.

## Edge resource behavior

- [ ] Make client, subscription, payload, mailbox, durable backlog, and journal limits explicit and configurable.
- [ ] Add low-memory admission behavior and metrics for rejected clients, queue pressure, dropped live messages, and backpressure.
- [ ] Add payload-size and topic-length validation tests across profiles.

## Security

- [ ] Define secure-by-default bind/authentication behavior for local and remote deployments.
- [ ] Add TLS/mTLS transport integration or clearly gate it before beta release.
- [ ] Verify ACL, tenant isolation, credential rotation, and management endpoint exposure rules.

## Reliability and edge links

- [ ] Integrate durable-session recovery with restart and power-loss-style failure tests.
- [ ] Integrate cursor-aware edge forwarding with reconnect, duplicate, gap, and bounded offline behavior.
- [ ] Add journal compaction/checkpoint behavior and disk-full handling.

## AI and application events

- [ ] Keep application payloads opaque bytes with content type, schema ID, correlation ID, reply subject, and trace metadata.
- [ ] Add documented patterns for telemetry, commands, inference requests, inference results, and model/version events.
- [ ] Do not place model inference or heavyweight serialization in the broker hot path.

## Performance and validation

- [ ] Run payload-size, publisher/subscriber, profile, fan-out, reconnect, and sustained soak benchmark matrices.
- [ ] Record accepted, delivered, acknowledged, redelivered, loss, duplicate, gap, latency, CPU, RSS, and queue pressure metrics.
- [ ] Add cross-target smoke tests and release artifact checksum verification.

## Release

- [ ] Synchronize version metadata, changelog, README, Mintlify docs, release notes, and beta gate checker.
- [ ] Run the complete CI, security, recovery, benchmark, soak, and packaging workflow.
- [ ] Create a 1.0.0-beta tag only when all advertised gates pass; otherwise publish an accurately labeled development release.

## Validation pause

- [ ] Keep the current branch quiet and do not push additional commits or manually retrigger CI until the user explicitly requests resumption.
- [ ] Preserve the latest completed CI evidence and inspect only the active run needed to confirm its final state.

## Final release resume

- [ ] Batch the remaining native release-gated changes before triggering the next CI cycle.
- [ ] Run one consolidated final validation cycle before deciding whether a final release tag is justified.
- [ ] Keep the final version and release notes aligned with only the capabilities supported by passing evidence.

## 1.0.0 completion request

- [ ] Continue implementation until the defined 1.0.0 release gates are either fully implemented and validated or explicitly documented as blockers.
- [ ] Batch code changes before the next consolidated CI trigger and do not bump version metadata prematurely.
- [ ] Prepare the final 1.0.0 release only after compile, integration, security, recovery, benchmark, soak, cross-target, and artifact checks pass.

## Edge transport and TLS release request

- [ ] Implement broker-integrated edge forwarding with bounded queues, cursor handling, reconnect, and authenticated link lifecycle.
- [ ] Implement native TLS/mTLS configuration or document an exact build/runtime blocker if the current Zig toolchain cannot support it safely.
- [ ] Run the complete final release validation and prepare artifacts only after all advertised gates pass.

## Edge transport completion

- [x] Integrate the existing LINK frame, cursor, authentication, and bounded-forwarder modules into broker-to-broker connections.
- [x] Add real TLS/mTLS listener configuration, certificate verification, and security regression tests.
- [ ] Do not bump to 1.0.0 or publish artifacts until edge transport and TLS/mTLS gates pass.

## Stacked PR release execution

- [ ] Preserve the merged main baseline and record the current working-tree changes.
- [ ] Stack PR 1 for validation tooling, disk-full/fault coverage, benchmark metadata, and evidence collection.
- [ ] Stack PR 2 for documentation synchronization and stable-claim/non-claim policy.
- [ ] Stack PR 3 for final packaging, release-candidate metadata, checksums, and tag-readiness workflow.
- [ ] Run CI and merge the stacked PRs in dependency order without creating v1.0.0 prematurely.

## Consolidated v1.0.0 blocker execution

- [ ] Complete the operational performance matrix and archive raw results.
- [ ] Run and archive the one-hour soak on the final candidate commit.
- [ ] Add or validate disk-full and broader fault-matrix behavior.
- [ ] Resolve credential rotation and identity-to-ACL mapping as tested claims or explicit non-claims.
- [ ] Synchronize stable-release documentation and known limitations.
- [ ] Run final metadata, stale-claim, link, checksum, and diff validation.
- [ ] Build final multi-target artifacts from one exact commit.
- [ ] Run consolidated final CI and inspect every required job.
- [ ] Prepare the approval/tag sequence without creating v1.0.0 before all gates pass.

## Beta.1 to final v1.0.0 review

- [x] Inspect the authoritative release gates, PR/CI state, metadata, artifacts, and working tree.
- [x] Classify mandatory final-release work separately from post-1.0 features.
- [x] Document exact acceptance evidence and the final tag sequence.

## Final CI and codebase audit

- [ ] Verify the corrected PR main test job and cross-target jobs.
- [ ] Audit remaining protocol, security, compatibility, operations, benchmark, documentation, and release gaps.
- [ ] Implement and test every concrete gap that is within the current scope.
- [ ] Push one batched update and recheck CI before reporting readiness.

## Pull request and CI verification

- [ ] Verify the candidate branch and working tree are ready for one batched PR.
- [ ] Push the branch and create or update the PR with release-gate context.
- [ ] Inspect all PR CI checks and record release/tag readiness.

## Full roadmap and beta audit

- [ ] Audit all planned versions through 0.15.0 and the 1.0.0-beta gates against the current repository.
- [ ] Produce an exact missing-version and missing-deliverable report.
- [ ] Implement remaining code, CI/CD, benchmark, soak, fuzz, compatibility, failure, and artifact gates.
- [ ] Re-run the full suite and update the final tag-readiness decision.

## Accelerated v1.0.0-beta execution

- [x] Replace direct net.Stream reader/writer coupling with a shared plain/TLS transport abstraction.
- [x] Wire TLS server/client handshakes, certificate loading, CA verification, and required mTLS client authentication.
- [ ] Run secure LINK, invalid-certificate, protocol, recovery, benchmark, soak, hostile-input, failure-injection, and cross-target gates in CI.
- [ ] Update beta metadata, changelog, artifacts, checksums, CI, and tag only after all selected beta gates pass in CI.

## Active beta implementation

- [x] Implement live TLS/mTLS transport in the broker connection lifecycle rather than compile-only vendoring.
- [x] Add certificate acceptance/rejection, secure edge-link, and regression tests.
- [x] Re-run all beta release gates before changing version metadata or tagging.

## v1.0.0 release preparation

- [x] Complete TLS/mTLS listener and edge-link runtime integration with certificate verification.
- [x] Add secure transport acceptance/rejection, certificate, compatibility, recovery, benchmark, soak, and artifact gates.
- [ ] Synchronize v1.0.0 metadata and create the tag only after the consolidated release gate passes.

## Remaining native implementation

- [x] Integrate broker-to-broker forwarding into the native connection lifecycle instead of leaving it as standalone primitives.
- [x] Wire the vendored Zig 0.15-compatible TLS server into listener/client transport, add certificate configuration, and add mTLS tests.
- [x] Run the final release gates only after the remaining code is integrated and compiled.
- [x] Continue this implementation run through the remaining code and validation rather than stopping at an intermediate status report.
