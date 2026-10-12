# Planbord

Een planbord dat werkt zoals Trello: borden, lijsten en kaarten die je kunt verslepen, met een Inbox en een weekplanner. Je kunt mails uit Outlook en andere bestanden als bijlage op kaarten slepen.

Het is een webapp die je kunt installeren (PWA) en die ook zonder internet werkt.

## Gebruiken

Open de app via GitHub Pages en installeer hem:

- **Computer (Chrome of Edge):** klik op "Installeren" bovenin de app.
- **iPhone:** in Safari tik je op Delen en dan op "Zet op beginscherm".
- **Android:** in Chrome kies je "App installeren".

Je gegevens (kaarten en bijlagen) worden op het apparaat zelf bewaard, in de opslag van de browser.

## Synchroniseren tussen apparaten

Planbord gebruikt Supabase voor inloggen en synchroniseren. Iedereen logt in met een eigen account en ziet alleen de eigen borden.

1. Voer `supabase/planbord-setup.sql` één keer uit in Supabase > SQL Editor.
2. Zet in Supabase > Authentication > URL Configuration de Site URL op het adres van de app.
3. Klik in de app rechtsboven op het rondje om in te loggen of een account te maken.

## Bestanden

- `index.html`: de hele app
- `manifest.webmanifest`: naam, kleuren en iconen voor installeren
- `sw.js`: zorgt dat de app offline werkt
- `icons/`: app-iconen
