import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { supabase } from './client';
import LiveBoard from './Live';
import type { Category, Opening, Rule } from './model';
import { categories, names, units } from './model';

type HitCounts=Record<Category,number>;
type GuestSection={
  id:string;
  mode:'single'|'mixed';
  display_ordinals:number[];
  opened_boosters:number;
  hits:HitCounts;
  status:'active'|'closed';
};
type GuestOpening={
  id:string;
  client_id:string;
  label:string;
  set_slug:string;
  kind:Opening['kind'];
  rule:Rule;
  created_at:string;
  status:'active'|'closed';
  submitted:boolean;
  sections:GuestSection[];
};
const STORAGE='pokemon-hit-tracker-guest-v1';
const zero=():HitCounts=>({sar:0,classics:0,ar:0,fur:0,rgb:0});
const totals=(o:GuestOpening)=>o.kind==='display'?1:o.kind==='case'?o.rule.displays_per_case:o.rule.displays_per_case*o.rule.cases_per_casecase;
const limit=(o:GuestOpening,c:'sar'|'classics'|'ar',displays:number)=>({sar:o.rule.sar_per_display,classics:o.rule.classics_per_display,ar:o.rule.ar_per_display})[c]*displays;
const guestLabel=(o:GuestOpening)=>o.label||units[o.kind];
const number=(n:number)=>n.toLocaleString('de-DE',{maximumFractionDigits:1});

function RateCards({opening,section}:{opening:GuestOpening;section:GuestSection}) {
 const displays=section.display_ordinals.length;
 const remaining=displays*20-section.opened_boosters;
 return <div className="rategrid">{(['sar','classics','ar'] as const).map(c=>{
  const guaranteed=limit(opening,c,displays);
  const normal=guaranteed/(displays*20)*100;
  const current=remaining>0?Math.max(0,guaranteed-section.hits[c])/remaining*100:null;
  const shade=current===null?'':current>normal+1e-8?'rate-high':current<normal-1e-8?'rate-low':'';
  return <div className="ratebox" key={c}><span>{names[c]}</span>
   <strong className={shade}>{current===null?'–':number(current)+' %'}</strong>
   <small>Normal: {number(normal)} %</small></div>;
 })}</div>;
}
function GuestTracker(){
 const [rules,setRules]=useState<Rule[]>([]);
 const [setLoadError,setSetLoadError]=useState('');
 const [openings,setOpenings]=useState<GuestOpening[]>(()=>{
  try {const value=JSON.parse(localStorage.getItem(STORAGE)||'[]');return Array.isArray(value)?value:[];}catch{return [];}
 });
 const [selectedId,setSelectedId]=useState<string|null>(null);
 const [kind,setKind]=useState<Opening['kind']>('case');
 const [setSlug,setSetSlug]=useState('30th-sc');
 const [label,setLabel]=useState('');
 const [mode,setMode]=useState<'single'|'mixed'>('single');
 const [chosen,setChosen]=useState<number[]>([]);
 const [busy,setBusy]=useState(false);
 const [notice,setNotice]=useState('');
 const [error,setError]=useState('');
 useEffect(()=>{try{localStorage.setItem(STORAGE,JSON.stringify(openings));}catch{setError('Lokale Speicherung ist nicht verfügbar. Deine Eingaben bleiben nur in dieser Sitzung.');}},[openings]);
 useEffect(()=>{
  let active=true;
  void supabase.from('app_sets').select('slug,title,displays_per_case,cases_per_casecase,sar_per_display,classics_per_display,ar_per_display,active').eq('active',true).then(r=>{
   if(!active)return;
   if(r.error){setSetLoadError(r.error.message);return;}
   const items=r.data as Rule[];
   setRules(items);
   if(items.length)setSetSlug(old=>items.some(x=>x.slug===old)?old:items[0].slug);
  });
  return()=>{active=false};
 },[]);
 const current=useMemo(()=>openings.find(x=>x.id===selectedId)||null,[openings,selectedId]);
 const available=current?Array.from({length:totals(current)},(_,i)=>i+1).filter(i=>!current.sections.some(g=>g.display_ordinals.includes(i))):[];
 const active=current?.sections.find(x=>x.status==='active');
 const setCurrent=(update:(g:GuestOpening)=>GuestOpening)=>{
  if(!selectedId)return;
  setOpenings(old=>old.map(g=>g.id===selectedId?update(g):g));
 };
 function create(){
  const rule=rules.find(x=>x.slug===setSlug);
  if(!rule){setError('Bitte ein Pokémon-Set auswählen.');return;}
  const total=kind==='display'?1:kind==='case'?rule.displays_per_case:rule.displays_per_case*rule.cases_per_casecase;
  if(total>72){setError('Maximal 72 Displays je Gastöffnung werden unterstützt.');return;}
  const id=crypto.randomUUID();
  const g:GuestOpening={id,client_id:crypto.randomUUID(),label:label.trim().slice(0,120),set_slug:rule.slug,kind,rule,created_at:new Date().toISOString(),status:'active',submitted:false,sections:[]};
  setOpenings(old=>[g,...old]);setSelectedId(id);setLabel('');setNotice('Neue Gastöffnung angelegt. Deine Daten werden zunächst nur in diesem Browser gespeichert.');setError('');
 }
 function start(){
  if(!current||current.status!=='active'||active)return;
  if((mode==='single'&&chosen.length!==1)||(mode==='mixed'&&chosen.length<2))return;
  if(chosen.some(i=>!available.includes(i)))return;
  const group:GuestSection={id:crypto.randomUUID(),mode,display_ordinals:[...chosen].sort((a,b)=>a-b),opened_boosters:0,hits:zero(),status:'active'};
  setCurrent(g=>({...g,sections:[...g.sections,group]}));setChosen([]);setNotice('Abschnitt gestartet.');
 }
 function updateActive(update:(section:GuestSection)=>GuestSection){
  setCurrent(g=>({...g,sections:g.sections.map(s=>s.status==='active'?update(s):s)}));
 }
 function adjustHit(c:Category,delta:number){
  if(!current||!active)return;
  const max=c==='fur'||c==='rgb'?Number.MAX_SAFE_INTEGER:limit(current,c,active.display_ordinals.length);
  const next=Math.max(0,Math.min(max,active.hits[c]+delta));
  updateActive(g=>({...g,hits:{...g.hits,[c]:next}}));
 }
 function changeBooster(value:number){
  if(!active||!Number.isInteger(value))return;
  const n=Math.max(0,Math.min(active.display_ordinals.length*20,value));
  updateActive(g=>({...g,opened_boosters:n}));
 }
 function closeSection(){
  if(!active||!window.confirm('Abschnitt manuell abschließen? Danach können die Werte dieses Abschnitts nicht mehr geändert werden.'))return;
  updateActive(g=>({...g,status:'closed'}));setNotice('Abschnitt abgeschlossen. Zusatzhits lassen sich nur vor dem manuellen Abschluss nachtragen.');
 }
 async function submitOpening(opening:GuestOpening){
  if(busy)return;
  setBusy(true);setError('');
  const payload={kind:opening.kind,label:opening.label,set_slug:opening.set_slug,
   sections:opening.sections.map(g=>({mode:g.mode,display_ordinals:g.display_ordinals,opened_boosters:g.opened_boosters,hits:g.hits,status:g.status}))};
  try{
   const r=await supabase.rpc('app_submit_guest_opening',{p_client_id:opening.client_id,p_payload:payload});
   if(r.error)throw r.error;
   setOpenings(old=>old.map(o=>o.id===opening.id?{...o,status:'closed',submitted:true}:o));
   setNotice('Eingereicht! Diese Statistik ist als „extern eingereicht · unter Vorbehalt“ gekennzeichnet und wird vor einer Freigabe geprüft.');
  }catch(e){setError(e instanceof Error?e.message:String(e))}
  finally{setBusy(false)}
 }
 function finish(){
  if(!current||active||current.sections.length===0)return;
  if(!window.confirm('Gesamte Öffnung abschließen und die Ergebnisse als externe Ziehung unter Vorbehalt einreichen?'))return;
  setCurrent(g=>({...g,status:'closed'}));
  void submitOpening({...current,status:'closed'});
 }
 function remove(){
  if(!current||window.prompt('Lokale Öffnung entfernen? Tippe LÖSCHEN:')!=='LÖSCHEN')return;
  setOpenings(old=>old.filter(g=>g.id!==current.id));setSelectedId(null);setNotice(current.submitted?'Lokale Kopie entfernt. Eine bereits eingereichte Statistik bleibt zur Prüfung gespeichert.':'Lokale Öffnung entfernt.');
 }
 const selectOrdinal=(n:number)=>setChosen(old=>mode==='single'?[n]:old.includes(n)?old.filter(i=>i!==n):[...old,n]);
 const fmt=(s:string)=>new Date(s).toLocaleString('de-DE',{dateStyle:'medium',timeStyle:'short'});
 return <div className="guest-tracker stack">
  <div className="guest-intro"><h2>Eigene Eskalation anlegen</h2><p className="muted">Ohne Konto: Displays oder Cases öffnen, Booster und Hits zählen, mischen und Statistiken unter Vorbehalt einreichen.</p>
   <p className="subtle">Deine laufenden Öffnungen werden lokal auf diesem Gerät gespeichert. Sie sind auf anderen Geräten nicht verfügbar.</p></div>
  {notice&&<div className="guest-notice">{notice}<button onClick={()=>setNotice('')} aria-label="Hinweis schließen">×</button></div>}
  {error&&<div className="alert">{error}<button onClick={()=>setError('')} aria-label="Fehler schließen">×</button></div>}
  {!current?<><section className="card stack">
    <h3>Neue eigene Öffnung</h3>
    {setLoadError&&<p className="alert">Set-Auswahl momentan nicht verfügbar: {setLoadError}</p>}
    <div className="forms"><label>Pokémon-Set<select value={setSlug} onChange={e=>setSetSlug(e.target.value)}>{rules.map(r=><option value={r.slug} key={r.slug}>{r.title}</option>)}</select></label>
    <label>Verpackung<select value={kind} onChange={e=>setKind(e.target.value as Opening['kind'])}><option value="display">Display · 20 Booster</option><option value="case">Case · 12 Displays</option><option value="case_case">Case-Case · 72 Displays</option></select></label>
    <label>Name (optional)<input value={label} maxLength={120} onChange={e=>setLabel(e.target.value)} placeholder="Meine Eskalation"/></label></div>
    <button className="primary" disabled={rules.length===0} onClick={create}>+ Eigene Eskalation starten</button>
   </section>
   <h3>Meine lokalen Eskalationen</h3>
   {openings.length===0?<section className="card"><p>Noch keine eigene Öffnung angelegt.</p></section>:openings.map(o=><button className="history" key={o.id} onClick={()=>{setSelectedId(o.id);setNotice('')}}>
    <strong>{guestLabel(o)}</strong><span>{units[o.kind]} · {fmt(o.created_at)}</span><span className="flag">{o.submitted?'Extern eingereicht · unter Vorbehalt':o.status==='closed'?'Nicht eingereicht':'Laufend'}</span></button>)}
  </>:<>
   <button className="textbutton" onClick={()=>{setSelectedId(null);setChosen([])}}>← Meine Eskalationen</button>
   <div className="between"><div><h2>{guestLabel(current)}</h2><p className="muted">{units[current.kind]} · {totals(current)} Displays · {fmt(current.created_at)}</p></div>
    <span className="flag">{current.submitted?'Unter Vorbehalt':current.status==='closed'?'Abgeschlossen':'Laufend'}</span></div>
   {active&&<section className="card stack">
     <div className="between"><h3>{active.mode==='mixed'?'Gemischter Boosterpool':'Einzelöffnung'}</h3><span className="flag">Aktiv</span></div>
     <p className="subtle">{active.display_ordinals.length} Displays · {active.display_ordinals.map(n=>'Display '+n).join(', ')}</p>
     <div className="between"><h3>Geöffnete Booster</h3><strong>{active.opened_boosters} / {active.display_ordinals.length*20}</strong></div>
     <progress className="live-progress" value={active.opened_boosters} max={active.display_ordinals.length*20}/>
     <div className="booster-edit"><button disabled={active.opened_boosters===0} onClick={()=>changeBooster(active.opened_boosters-1)}>−</button>
      <label>Bereits geöffnet<input type="number" step={1} min={0} max={active.display_ordinals.length*20} value={active.opened_boosters} onChange={e=>changeBooster(Number(e.target.value))}/></label>
      <button disabled={active.opened_boosters===active.display_ordinals.length*20} onClick={()=>changeBooster(active.opened_boosters+1)}>+</button></div>
     <div className="countergrid">{categories.map(c=>{
      const max=c==='fur'||c==='rgb'?null:limit(current,c,active.display_ordinals.length);
      return <div className="counter" key={c}><span>{names[c]}</span>
       <strong>{active.hits[c]}{max!==null&&<small> / {max}</small>}</strong>
       <div className="pair"><button disabled={active.hits[c]===0} onClick={()=>adjustHit(c,-1)} aria-label={names[c]+' reduzieren'}>−</button>
        <button disabled={max!==null&&active.hits[c]>=max} onClick={()=>adjustHit(c,1)} aria-label={names[c]+' erhöhen'}>+</button></div></div>;
     })}</div>
     {active.mode==='mixed'&&<><h3>Verbleibende Hit-Raten</h3><RateCards opening={current} section={active}/>
       <p className="subtle">Rechnerische Restquoten der garantierten Hits. Rot unter dem Normalwert, grün darüber; FUR/RGB zählen separat.</p></>}
     <button className="secondary" onClick={closeSection}>Abschnitt manuell abschließen</button>
    </section>}
   {!active&&current.status==='active'&&available.length>0&&<section className="card stack">
    <h3>Nächsten Abschnitt starten</h3><p className="subtle">Nur vollständig ungeöffnete Displays können einem neuen Pool zugewiesen werden.</p>
    <div className="switch"><button className={mode==='single'?'chosen':''} onClick={()=>{setMode('single');setChosen([])}}>Einzeln</button><button className={mode==='mixed'?'chosen':''} onClick={()=>{setMode('mixed');setChosen([])}}>Booster mischen</button></div>
    <div className="displaygrid">{available.map(n=><button className={chosen.includes(n)?'display selected':'display'} onClick={()=>selectOrdinal(n)} key={n}>
      {current.kind==='display'?'Display 1':'Case '+(Math.floor((n-1)/current.rule.displays_per_case)+1)+' · Display '+(((n-1)%current.rule.displays_per_case)+1)}
     </button>)}</div>
    <p className="subtle">{chosen.length} von {available.length} verfügbaren Displays ausgewählt</p>
    <button className="primary" disabled={mode==='single'?chosen.length!==1:chosen.length<2} onClick={start}>Abschnitt starten</button>
   </section>}
   {current.sections.filter(g=>g.status==='closed').length>0&&<section className="card stack"><h3>Abgeschlossene Abschnitte</h3>
    {current.sections.filter(g=>g.status==='closed').map(g=><div key={g.id} className="guest-section-summary">
     <strong>{g.mode==='mixed'?'Gemischt':'Einzeln'} · {g.display_ordinals.length} Displays · {g.opened_boosters}/{g.display_ordinals.length*20} Booster</strong>
     <p className="subtle">{categories.map(c=>names[c]+': '+g.hits[c]).join(' · ')}</p></div>)}
    </section>}
   {current.status==='active'&&!active&&<section className="card stack">
     <h3>Gesamte Öffnung abschließen</h3>
     <p className="subtle">Damit werden die erfassten Abschnitte als externe Ziehung unter Vorbehalt gespeichert. Nicht geöffnete Displays werden nicht als geöffnet gezählt.</p>
     <button className="primary" disabled={busy||current.sections.length===0} onClick={finish}>{busy?'Einreichen …':'Abschließen und Statistik einreichen'}</button>
    </section>}
   {current.status==='closed'&&!current.submitted&&<section className="card stack"><h3>Einreichung ausstehend</h3>
    <p className="subtle">Die Öffnung ist lokal abgeschlossen, aber noch nicht an die Gesamtstatistik übertragen. Bitte erneut versuchen.</p>
    <button className="primary" disabled={busy} onClick={()=>void submitOpening(current)}>{busy?'Einreichen …':'Erneut unter Vorbehalt einreichen'}</button></section>}
   {current.submitted&&<section className="card"><p><strong>Extern eingereicht · unter Vorbehalt.</strong> Die Statistik ist gespeichert. Ein Administrator kann sie prüfen und freigeben.</p></section>}
   <section className="card"><h3>Lokale Öffnung löschen</h3><p className="subtle">Eine bereits eingereichte Statistik bleibt auf dem Server erhalten und kann nur administrativ entfernt werden.</p>
    <button className="secondary" onClick={remove}>Lokale Öffnung löschen</button></section>
  </>}
 </div>;
}
export default function GuestPortal({loginForm}:{loginForm:ReactNode}){
 const [mode,setMode]=useState<'watch'|'guest'>('watch');
 const [login,setLogin]=useState(false);
 return <div className="guest-portal">
  <div className="guest-choice" role="group" aria-label="Eskalation auswählen">
   <button className={mode==='watch'?'active':''} onClick={()=>setMode('watch')}>
    <strong>Aktuelle Eskalation ansehen</strong><span>Live verfolgen – ohne Anmeldung</span></button>
   <button className={mode==='guest'?'active':''} onClick={()=>setMode('guest')}>
    <strong>Eigene Eskalation anlegen</strong><span>Selbst ziehen, zählen und einreichen</span></button>
  </div>
  {mode==='watch'?<LiveBoard/>:<GuestTracker/>}
  <div className="guest-login-link"><button className="textbutton" onClick={()=>setLogin(!login)}>
   {login?'Anmeldung ausblenden':'Bereits registriert? Anmelden oder registrieren'}</button>
   {login&&loginForm}
  </div>
 </div>;
}
