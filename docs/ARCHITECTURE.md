# Architecture

**Overview**
The project is structurally split into three main pieces:

1. **Data Collection** - scripts/Collect-CACertData.ps1
This script handles the heavy lifting, autonomously querying the Active Directory Enterprise CA and checking the local certificate store, and outputs everything into a simple flat file (data/ca_data.json).

2. **Dashboard UI** - index.html, app.js, cacert.js, styles.css
This serves as the frontend layer. It seamlessly reads the JSON drop and paints the dashboard interface, automatically sorting certificates into Valid, Warning, and Critical categories to prevent manual digging through logs.

3. **Web Server** - scripts/serve.ps1
A significantly lightweight, standalone .NET web listener that hosts the dashboard cleanly on a dedicated port (default 8089).

<br>

**Runtime Flow**
AD / Cert Store → Collect-CACertData.ps1 → data/ca_data.json → serve.ps1 → browser

<br>

**Setup Flow (Setup-CACertDashboard.ps1)**
[1/6]  Create install directories
[2/6]  Copy web files and scripts appropriately
[3/6]  Configure the web listener (serve.ps1)
[4/6]  Certificate Enrollment
       Option 1: Self-Signed (New-DashboardCert.ps1)
       Option 2: Enterprise CA (Request-CACert.ps1)
[5/6]  Register scheduled tasks (WebServer and Collector)
[6/6]  Start tasks, trigger initial collection, open firewall

<br>

**Update Flow (Update-CACertDashboard.ps1)**
[1/3]  Copy and overwrite HTML, JS, CSS, and scripts
[2/3]  Bounce the web server scheduled task
[3/3]  Trigger a manual data collection for immediate UI telemetry

<br>

**How It Fits In**
- Standalone but friendly: It runs completely autonomously. It does not require the Kiosk or Admin RTX dashboards to be installed, but if they are present, they all integrate nicely together.
- No CORS blocks: Moving to a localized flat data pipeline ensures cross-origin blocks and polling errors are entirely averted.
- Complete IIS avoidance: The web server explicitly binds to its own port. IIS is bypassed completely, ensuring zero chance of accidentally interrupting active MECM or WSUS services.
- Isolated collection: Data parsing runs safely under an isolated scheduled task account.

<br>

**Key Design Decisions**
*Local JSON Payload vs DB*: SQL dependencies were entirely avoided. A flat JSON file is exponentially faster, portable, and incredibly easy to troubleshoot in real-time.

*Enterprise CA Automation*: Automating the certreq payload flow generates authentic, domain-trusted SSL boundaries right out of the box.

*Custom HTTP Listeners*: Using dedicated .NET HTTPListeners keeps infrastructure footprint minimal and isolated.

*Re-using existing certs*: The architecture intelligently checks certlm.msc for valid (7+ day) certs and overrides the CA request menu to reuse them, significantly accelerating deployment time.
