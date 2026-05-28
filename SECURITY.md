# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in zenith, please report it
**privately** using GitHub's [Private vulnerability reporting][gh-psirt]
feature on this repository.

Please do **not** open a public issue or pull request for security
findings — disclosing before a patch ships can put users and
integrators at risk.

A useful report includes:

- A description of the issue and the affected contract(s) / line(s)
- Steps to reproduce, or a proof-of-concept
- Your assessment of impact and which actors are affected
  (users, fillers, sequencers, the sequencer admin)
- Any suggested remediation

Maintainers will acknowledge reports and provide initial triage as
soon as practical.

## Disclosure Timeline

Responsible disclosure is appreciated. A typical industry-standard
window is 90 days between report and public disclosure, extendable
when a fix requires ecosystem coordination (e.g. fillers updating
off-chain infrastructure).

## Scope

In scope:

- All contracts under `src/`

Out of scope:

- Issues in dependencies under `lib/` — please report upstream to the
  respective project
- Test contracts under `test/`

## Bug Bounty

There is no formal bug bounty program at the time of this writing.
Researchers who follow this policy may be acknowledged in patch
release notes at the maintainers' discretion.

[gh-psirt]: https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability
