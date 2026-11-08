# Basis and open questions

## What this chapter establishes

This chapter is an architecture-level synthesis of research into Arc 1.172.1 /
ArcCore 157.0.8103.39, arm64. It explains responsibilities and capabilities in
our own words. The underlying binary exports, decompiler output and local
research materials are not included in this repository.

Static analysis, architectural interpretation and observed behavior are
different kinds of support. The reference findings summarized here are static;
they do not establish runtime delivery, timing or universal safety. Statements
about architectural purpose interpret the structure, rather than quote the
original team's internal design decisions.

## Reading the conclusions

- The four logical layers explain responsibility; framework packaging does not
  determine the owner of every mechanism.
- An implementation of a Chromium hook is different from adding a new method
  to a shared Chromium interface.
- Selected control paths do not establish all senders, consumers or lifetimes.
- Capability presence does not establish effective configuration or product use.
- A reference capability does not become an OA requirement without an explicit
  adoption decision.

## Questions still open

| Question | Where the answer belongs |
| --- | --- |
| Exact original source changes | Not reconstructed; source edits and link-time replacement can look alike |
| Every new-page sender and final owner | Chromium / native-integration ownership contracts |
| Exact host/domain/port policy for Peek and related placement | App / ADK |
| Every completion, drop, cancel and teardown path | Specific native, Chromium or supplied-library contracts |
| Permission persistence and effective site isolation | More detailed contracts and separate runtime verification |
| Effective flags, live traffic filtering, sandbox enforcement and executed quit/crash behavior | Runtime observation |
| Which reference capabilities OA should adopt | OA product and architecture decisions |

This is a high-level question list, not a completion percentage. The overall
architecture can be useful while individual mechanisms remain partially known.

## Using the documentation for OA

Use the architecture to understand responsibilities and formulate design
questions. Implement OA from Chromium and Apple public sources, with its own
interfaces, configuration and assets. This documentation does not claim source
equivalence or implementation parity with the reference.

Future edits should name the owning layer, provide public references when
available, state material uncertainty and distinguish a proposal from an
accepted decision or an observed result.

Return to the [Chromium chapter](README.md).
