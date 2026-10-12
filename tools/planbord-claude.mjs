#!/usr/bin/env node
// Hulpje voor Claude (of jezelf) om Planbord via de sleutel uit de app te lezen en opdrachten klaar te zetten.
// De sleutel staat in de omgevingsvariabele PLANBORD_SLEUTEL. Zie supabase/claude-toegang.sql.
//
//   node tools/planbord-claude.mjs lijst
//   node tools/planbord-claude.mjs toevoegen '{"titel":"Logboek afmaken","bord":"Mijn bord","lijst":"Vandaag","datum":"2026-10-15"}'
//   node tools/planbord-claude.mjs klaar <kaart-id>
//   node tools/planbord-claude.mjs archiveren <kaart-id>
//   node tools/planbord-claude.mjs intrekken <opdracht-id>
//
// Velden bij toevoegen: titel (verplicht), bord, lijst (naam of id; zonder lijst gaat de kaart naar de Inbox),
// beschrijving, datum (JJJJ-MM-DD) en checklist (lijst met teksten).

const SUPA_URL = 'https://aevmzeukvermrbcakawd.supabase.co', SUPA_KEY = 'sb_publishable_Ks-0RV5qr3Ew5HvzJ5qCoQ_KWmUdkkR';
const sleutel = process.env.PLANBORD_SLEUTEL;
if (!sleutel) { console.error('Zet eerst PLANBORD_SLEUTEL (maak de sleutel in de app via Account > Sleutel voor Claude maken).'); process.exit(1); }

async function rpc(naam, args) {
  const r = await fetch(`${SUPA_URL}/rest/v1/rpc/${naam}`, {
    method: 'POST', headers: { apikey: SUPA_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ sleutel, ...args }),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw new Error((j && (j.message || j.hint)) || `Fout ${r.status}`);
  return j;
}

const [cmd, arg] = process.argv.slice(2);
try {
  if (cmd === 'lijst') {
    const { state, bijgewerkt, wachtend } = await rpc('claude_borden', {});
    if (!state) { console.log('Nog geen borden gesynchroniseerd.'); process.exit(0); }
    const kaart = (c, extra = '') => `    - ${c.done ? '[x]' : '[ ]'} ${c.title}${c.due ? ` (${c.due})` : ''}${extra}  id=${c.id}`;
    console.log(`Laatst gesynchroniseerd: ${bijgewerkt}\n\nInbox`);
    (state.inbox || []).forEach(c => console.log(kaart(c)));
    for (const b of state.boards || []) {
      console.log(`\nBord: ${b.title}  id=${b.id}`);
      for (const l of b.lists) { console.log(`  Lijst: ${l.title}  id=${l.id}`); l.cards.forEach(c => console.log(kaart(c))); }
    }
    if (wachtend.length) { console.log('\nWachtende opdrachten (worden uitgevoerd zodra de app open is):'); wachtend.forEach(w => console.log(`  ${w.id}: ${JSON.stringify(w.opdracht)}`)); }
  } else if (cmd === 'toevoegen') {
    console.log('Opdracht', await rpc('claude_opdracht', { opdracht: { soort: 'toevoegen', ...JSON.parse(arg) } }), 'klaargezet.');
  } else if (cmd === 'klaar' || cmd === 'archiveren') {
    console.log('Opdracht', await rpc('claude_opdracht', { opdracht: { soort: cmd, kaart: arg } }), 'klaargezet.');
  } else if (cmd === 'intrekken') {
    console.log((await rpc('claude_opdracht_intrekken', { opdracht_id: Number(arg) })) ? 'Ingetrokken.' : 'Niet gevonden (misschien al uitgevoerd).');
  } else {
    console.log('Gebruik: lijst | toevoegen <json> | klaar <kaart-id> | archiveren <kaart-id> | intrekken <opdracht-id>');
  }
} catch (e) { console.error(e.message); process.exit(1); }
