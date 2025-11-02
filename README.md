# wsl-webdevelopment-server
Dit is een voorgedefineerde installatie voor een WSL omgeving binnen windows. Je kan dit zien als een localhost installatie op windows voor webdevelopment op je eigen windows PC.
Het verschil tussen een localhost van windows zelf of een localhost via XAMPP of vergelijkbaar systeem is dat je met WSL je eigen Linux distrubution kan kiezen en daarop je eigen webserver kan inrichten.

## WSL - Ubuntu
Om te beginnen moet je WSL installeren. Dit wordt uitgelegd op de officiele windows website, maar daaronder heb ik even een samevatting geplaatst.
https://learn.microsoft.com/en-us/windows/wsl/install

Open PowerShell als administrator
Run: WSL --install

Nu heb je een Linux omgeving in je windows. In je windows verkenner zie je nu naast je schijven/netwerkschijven ook een Linux schijf. Deze schijf is nog leeg en daarop gaan we een distro installeren. Wij kiezen voor Ubuntu.

Run: WSL --install ubuntu.
Na installatie zal er gevraagd worden om een gebruiker aan te maken. Doe dit met een voor jouw logische gebruikersnaam en wachtwoord. 

Nu heb je een complete ubuntu omgeving welke je met WSL kunt benaderen.

We gaan deze ubuntu omgeving inrichten als een webserver welke te benaderen is via http://localhost
Hiervoor is een script klaargezet die de installatie runt voor je.

Run: curl -s https://raw.githubusercontent.com/daanwilson/wsl-webdevelopment-server/refs/heads/main/install.sh | bash

