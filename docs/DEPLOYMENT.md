# Deployment Guide

**Prerequisites**
- Network: Reachability to Active Directory Certificate Services (AD CS).
- Account: Local Administrator credentials.
- Dependencies: Powershell 5.1+

**Initial Setup**
The entire setup process is aggressively automated to streamline deployment.

1. Unzip the release to a staging folder.
2. Open PowerShell as Administrator.
3. Run .\scripts\Setup-CACertDashboard.ps1

**Deployment Options**
- InstallPath: Where the dashboard files reside. Default: C:\RTX-Dashboard-CA-Status
- DashboardPort: Port to bind the dashboard web listener. Default: 8089
- CollectInterval: Data collection frequency in minutes. Default: 60 (also prompted interactively during setup)
- TaskAccount: Windows account for scheduled tasks. Default: SYSTEM
- TaskPassword: Password for TaskAccount (used with -Force for unattended deployments with a named account).
- Force: Skips all interactive prompts and installs with current defaults.

**Scheduled Task Account**
By default, both scheduled tasks (web server and data collector) run as SYSTEM. This works for most member-server deployments where SYSTEM has network access to the CA hosts over TCP 135 / dynamic RPC.

> **Domain Controller scenario:** If your Enterprise CA is hosted on a Domain Controller locked down to Domain Admin accounts, SYSTEM will be blocked from issuing certutil RPC queries. In this case, the setup script will prompt for a service account (e.g. `DOMAIN\SVC-CA-Reader`) with Domain Admin or CA Read privileges. The account is enrolled with Password logon type in the scheduled task. For unattended deployment with a named account, pass `-TaskAccount` and `-TaskPassword` explicitly alongside `-Force`.

**SSL Modes**
1. Enterprise CA (Recommended): This queries the domain's AD CS to provision a real, trusted certificate, preventing browser security warnings. If a valid template isn't auto-detected, the script prompts for a dynamic selection. It explicitly checks for an existing, valid dashboard certificate beforehand and securely reuses it to maximize efficiency.
2. Self-Signed: Automatically generates a 10-year generic self-signed certificate. This allows immediate installation but will present untrusted connectivity warnings on remote sessions.



**Updating**
To apply a structural version bump, execute the update script. It overrides the HTML/JS/CSS structural paths without blowing away persistent scheduled tasks or server parameters.

.\scripts\Update-CACertDashboard.ps1 -InstallPath "C:\RTX-Dashboard-CA-Status"

It patches the new code over safely and bounces the scheduled tasks so changes take effect immediately with actively refreshed telemetry.



**Uninstallation**
If the dashboard ever needs to be removed from the server, the process is clean and decisive:

.\scripts\Remove-CACertDashboard.ps1 -InstallPath "C:\RTX-Dashboard-CA-Status" -Confirm:$false

This gracefully halts and unregisters the scheduled tasks, cleans down the Windows firewall rules, and purges the installation directory so it leaves nothing behind.
