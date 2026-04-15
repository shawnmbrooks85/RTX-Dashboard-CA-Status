# Information Architecture

**Goal**
The dashboard is structurally organized to surface the health and expiration timeline of the enterprise certificate infrastructure quickly, effectively eliminating the need for manual, time-consuming queries against Active Directory or local snap-ins.

**Primary Sections**
1. Enterprise CA Certificates
An interactive table showing all healthy, domain-trusted certificates dynamically discovered from the active AD environment.

2. Expiring and Warning Certificates
Highlights any certificates within 30 days of expiration, prioritizing them so renewals can be aggressively managed before service breaks.

3. Self-Signed / Local Certificates
Isolates locally bound certificates used as fallbacks. It verifies their validity and tracks their lifecycle independently of the Primary AD CS infrastructure.

**Data Ownership**
- UI modules are exclusively rendered from the standalone data/ca_data.json data drop.
- The interface inherently makes zero external calls; it solely depends on the localized telemetry payload that the local collector processes.

**Navigation Pattern**
- Highly linear and focused single-page view.
- Colorized badge states and dynamic sorting float the most urgent or soon-to-expire certificates straight to the top of the view logic.
- The UI is engineered strictly for scanning and visibility, ensuring that the actual administrative renewals continue happening within MMC or PowerShell natively.

**File Manifest (For IA Review)**

*Frontend & Core Assets*
- index.html: Structural DOM layout and container rendering targets.
- styles.css: Defines graphical layouts, colors, and dynamic rendering properties.
- app.js: The core Javascript parsing unit that handles the live clock and telemetry fetch loops.
- cacert.js: The visualization engine that ingests the JSON telemetry payload and actively sorts, parses, and formats certificate data based on expiration timelines.
- faq.html: Front-facing user documentation summarizing technical behaviors.
- rtx_logo.svg: Graphical asset for dashboard presentation.
- data/ca_data.json: (Dynamic) The structural data drop file populated by the data collection script.

*Backend Scaffolding*
- scripts/Setup-CACertDashboard.ps1: The foundational deployment script. Registers scheduled tasks, generates install directories, configures bindings, and provisions firewall scopes.
- scripts/Remove-CACertDashboard.ps1: Reversal logic that explicitly purges firewall rules, scheduled tasks, and local paths.
- scripts/Update-CACertDashboard.ps1: Pushes modified frontend HTML/JS structural updates directly over active deployments to avoid re-deploying scheduled tasks.
- scripts/serve.ps1: A lightweight .NET HTTPListener script acting as an autonomous standalone web server.
- scripts/Collect-CACertData.ps1: The central engine. Queries AD Enterprise infrastructure and local machine stores dynamically to export the flat ca_data.json stream.
- scripts/Request-CACert.ps1: Automates the certreq payload pipeline to enroll an authentic AD Enterprise Certificate.
- scripts/New-DashboardCert.ps1: A fallback module to automatically generate isolated self-signed certificates as a redundancy mechanism if Enterprise AD is unavailable.
