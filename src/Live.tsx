import { useCallback, useEffect, useState } from 'react';
import { supabase } from './client';

type Hits = { sar:number; classics:number; ar:number; fur:number; rgb:number };
type LiveGroup = {
  mode:'single'|'mixed';
  displays:number;
  opened_boosters:number;
  total_boosters:number;
  hits:Hits;
  targets:Pick<Hits,'sar'|'classics'|'ar'>;
};
type Snapshot = {
  label:string;
  kind:string;
  set_slug:string;
  total_displays:number;
  active_group:LiveGroup|null;
  total_hits:Hits;
};
type LiveRow = { public_id:string; updated_at:string; snapshot:Snapshot };
const categories = ['sar','classics','ar'] as const;
const labels = {sar:'SAR',classics:'Classics',ar:'AR'};
const format = (value:number) => value.toLocaleString('de-DE',{maximumFractionDigits:1});
function HitRates({group}:{group:LiveGroup}) {
  const boosters = group.total_boosters-group.opened_boosters;
  return <div className="rategrid">{categories.map(c=>{
    const normal = group.displays>0 ? group.targets[c]/group.total_boosters*100 : 0;
    const left = Math.max(0,group.targets[c]-group.hits[c]);
    const current = boosters>0 ? left/boosters*100 : null;
    const color = current===null ? '' : current>normal+1e-8 ? 'rate-high' : current<normal-1e-8 ? 'rate-low' : '';
    return <div className="ratebox" key={c}><span>{labels[c]}</span>
      <strong className={color}>{current===null ? '–' : format(current)+' %'}</strong>
      <small>Normal: {format(normal)} %</small></div>;
  })}</div>;
}
function LiveCard({item}:{item:LiveRow}) {
  const s=item.snapshot,g=s.active_group;
  const link = new URL(window.location.href);
  link.searchParams.set('watch',item.public_id);
  return <section className="card stack live-card">
    <div className="between"><div><span className="eyebrow">● Öffentliche Live-Ziehung</span>
      <h2>{s.label}</h2><p className="muted">{s.set_slug} · {s.total_displays} Displays</p></div>
      <span className="flag">Nur ansehen</span></div>
    {g ? <>
      <div><h3>{g.mode==='mixed'?'Gemischter Boosterpool':'Einzelöffnung'}</h3>
      <p className="muted">{g.displays} Displays · {g.opened_boosters} von {g.total_boosters} Boostern geöffnet</p>
      <progress className="live-progress" max={Math.max(1,g.total_boosters)} value={g.opened_boosters}/></div>
      <div className="rategrid">{(['sar','classics','ar','fur','rgb'] as const).map(c=><div className="ratebox" key={c}>
        <span>{c==='classics'?'Classics':c.toUpperCase()}</span>
        <strong>{g.hits[c]}{c!=='fur'&&c!=='rgb'?<small> / {g.targets[c]}</small>:null}</strong>
      </div>)}</div>
      <h3>Rest-Hitraten (garantierte Hits)</h3><HitRates group={g}/>
    </> : <p className="muted">Momentan kein aktiver Boosterpool. Die Ziehung wird fortgesetzt, sobald ein neuer Abschnitt beginnt.</p>}
    <p className="subtle">Gesamt bisher: SAR {s.total_hits.sar} · Classics {s.total_hits.classics} · AR {s.total_hits.ar} · FUR {s.total_hits.fur} · RGB {s.total_hits.rgb}</p>
    <div className="between"><small>Stand: {new Date(item.updated_at).toLocaleTimeString('de-DE')}</small><a href={link.toString()} className="live-link">Link zur Live-Ziehung</a></div>
  </section>;
}
export default function LiveBoard({back}:{back?:()=>void}) {
  const watch=new URLSearchParams(window.location.search).get('watch');
  const [rows,setRows]=useState<LiveRow[]>([]);
  const [error,setError]=useState('');
  const [loaded,setLoaded]=useState(false);
  const load=useCallback(async()=>{
    const r=await supabase.from('app_live_feed').select('public_id,updated_at,snapshot').order('updated_at',{ascending:false});
    if(r.error){setError(r.error.message);setLoaded(true);return;}
    setRows(r.data as LiveRow[]);setError('');setLoaded(true);
  },[]);
  useEffect(()=>{
    void load();
    const channel=supabase.channel('read-only-live-feed')
      .on('postgres_changes',{event:'*',schema:'public',table:'app_live_feed'},()=>{void load()})
      .subscribe();
    const timer=window.setInterval(()=>{void load()},20000);
    return ()=>{window.clearInterval(timer);void supabase.removeChannel(channel);};
  },[load]);
  const visible=watch?rows.filter(x=>x.public_id===watch):rows;
  return <div className="live-page stack">
    {back&&<button className="textbutton" onClick={back}>← Zurück</button>}
    <header><span className="eyebrow">Pokémon Hit Tracker</span><h1>Live-Ziehungen</h1>
      <p className="muted">Ohne Anmeldung ansehen · automatische Aktualisierung · keine Bearbeitung möglich</p></header>
    {error&&<p className="alert">{error}</p>}
    {!loaded&&<p className="muted">Live-Ziehungen werden geladen …</p>}
    {loaded&&visible.length===0&&!error&&<section className="card"><h3>Zurzeit keine öffentliche Live-Ziehung</h3><p className="muted">Es werden nur Öffnungen gezeigt, deren Besitzer die öffentliche Freigabe ausdrücklich aktiviert hat.</p></section>}
    {visible.map(x=><LiveCard item={x} key={x.public_id}/>)}
    <p className="subtle">Die Rest-Hit-Rate ist eine rechnerische Quote aus noch garantierten Hits und verbleibenden Boostern, keine unabhängige Vorhersage für einzelne Booster.</p>
  </div>;
}
