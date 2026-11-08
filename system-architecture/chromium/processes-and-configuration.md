# Processes and configuration

The reference extends Chromium's startup, profile services and child-process
plumbing so native integration can configure and use the engine.

## Browser and profile services

Startup hooks register extra work and observers. Profile-keyed modules integrate
ad blocking, history, site settings and extension-facing configuration. Chromium
provides the surrounding profile/service lifetime machinery; native integration
supplies inputs and exposes selected operations upward.

Private browsing uses Chromium's off-the-record profile machinery. A native
wrapper disappearing is not the same event as the underlying profile being
destroyed. Likewise, production termination's flush-and-reply path is distinct
from the optional orderly teardown path. A termination reply does not prove all
flushes succeeded or every native object was destroyed.

## Added utility work

| Work | Engine-side role | Use through ArcCore |
| --- | --- | --- |
| AI | Utility service and request/result plumbing | Expose service operations to native callers |
| Content conversion | HTML-to-Markdown processing with conversion options | Submit content and receive a structured result |
| HEIF decoding | Image-decoder utility integration | Use a dedicated decoding service path |
| Profile import | Utility import pipeline and browser-side coordination | Submit an import and forward progress/results upward |

These modules are present in the studied artifact. That does not establish which
product UI enabled them. Disconnect, failure, capture release and backend
cancellation differ across services; no universal cancellation guarantee was
recovered.

## Configuration and build choices

The reference adds a startup-feature registry, compiled Chromium feature
overrides and child-process switches. A serialized startup-feature snapshot is
sent to utility children; renderers receive selected Blink settings through
their own switches. Some directory and application-identification switches
apply across child types.

This separates several questions: what a feature's declaration defaults to,
what the compiled overrides select, what configuration the app supplies, and
what a running process ultimately uses. Static evidence does not collapse those
questions into one effective setting.

Media integration includes an AudioToolbox AAC decoder registered inside FFmpeg.
That is an engine/build choice rather than a native app playback implementation.

## Security and diagnostics

The artifact contains custom sandbox policies for AI/conversion and HEIF, plus
renderer and GPU policy changes. The mapped importer launch uses an unsandboxed
service type. These describe static policy and launch configuration; effective
enforcement requires observation.

Permissions, certificate handling, cookie/storage policy and site isolation
retain Chromium machinery with selected custom hooks and native integration.
Later research narrows specific paths but does not prove universal late-reply
safety, durable permission storage or effective isolation.

Diagnostics include GPU observation, histogram callbacks, crash-annotation
forwarding and integration with a Sentry-based reporting path. A static report
submission path does not prove a crash was captured or uploaded.

## OpenArch direction

OA needs an explicit Chromium version pin, build configuration, patch series
and security-update process. The relationship between the native app's lifecycle
and Chromium's run loop also needs a defined contract. This reference chapter
does not choose OA's service inventory, codec distribution, sandbox policies
or telemetry settings.


Return to the [Chromium chapter](README.md).
