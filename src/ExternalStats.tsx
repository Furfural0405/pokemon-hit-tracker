import {useEffect,useState} from 'react';
import {supabase} from './client';
type ExternalHitCounts={sar:number;classics:number;ar:number;fur:number;rgb:number};
type Submission={
 id:string;set_slug:string;kind:'display'|'case'|'case_case';label:string;
 total_displays:number;recorded_displays:number;eligible_displays:number;
 status:'pending'|'approved'|'rejected';source:'external';
 created_at:string;hits:ExternalHitCounts;
};
const sums=(items:Submission[],key:keyof ExternalHitCounts)=>
 items.reduce((n,x)=>n+(Number(x.hits?.[key])||0),0);
function useGuestSubmissions(version:number){
 const [items,setItems]=useState<Submission[]>([]);
 const [error,setError]=useState('');
 useEffect(()=>{
  let active=true;
  void supabase.from('app_guest_submissions').select('id,set_slug,kind,label,total_displays,recorded_displays,eligible_displays,status,source,created_at,hits')
   .order('created_at',{ascending:false}).limit(500).then(({data,error:e})=>{
    if(!active)return;
    if(e)setError(e.message);
    else{setItems(data as Submission[]);setError('');}
   });
  return()=>{active=false};
 },[version]);
 return {items,error};
}
export function ExternalStats({version,setSlug,personal}:{version:number;setSlug:string;personal:{openings:number;fur:number;rgb:number}}){
 const {items,error}=useGuestSubmissions(version);
 const filtered=items.filter(x=>setSlug==='all'||x.set_slug===setSlug);
 const approved=filtered.filter(x=>x.status==='approved');
 const pending=filtered.filter(x=>x.status==='pending');
 const verifiedFur=personal.fur+sums(approved,'fur');
 const verifiedRgb=personal.rgb+sums(approved,'rgb');
 return <section className="card stack external-stats">
  <div><h3>Gesamtstatistik mit externen Einreichungen</h3>
    <p className="subtle">Verifizierte eigene Daten und von Gästen eingereichte Ziehungen sind getrennt ausgewiesen. Ungeprüfte Ergebnisse erscheinen nur bei Administratoren und gelten ausdrücklich unter Vorbehalt.</p></div>
  {error&&<p className="alert">{error}</p>}
  <div className="external-stat-grid">
   <div><small>Eigene Öffnungen</small><strong>{personal.openings}</strong></div>
   <div><small>Externe · freigegeben</small><strong>{approved.length}</strong></div>
   <div><small>Externe · unter Vorbehalt</small><strong>{pending.length}</strong></div>
  </div>
  <div className="external-stat-grid">
   <div><small>FUR · eigene + freigegebene</small><strong>{verifiedFur}</strong></div>
   <div><small>RGB · eigene + freigegebene</small><strong>{verifiedRgb}</strong></div>
   <div><small>FUR / RGB · inkl. Vorbehalt</small><strong>{verifiedFur+sums(pending,'fur')} / {verifiedRgb+sums(pending,'rgb')}</strong></div>
  </div>
  <p className="subtle">Externe SAR/Classics/AR-Hits · freigegeben: {sums(approved,'sar')} / {sums(approved,'classics')} / {sums(approved,'ar')}
   {pending.length>0?' · unter Vorbehalt: '+sums(pending,'sar')+' / '+sums(pending,'classics')+' / '+sums(pending,'ar'):''}</p>
  {filtered.filter(x=>x.status!=='rejected').length>0&&<div className="tablewrap"><table>
   <thead><tr><th>Externe Ziehung</th><th>Erfasste Displays</th><th>SAR</th><th>Classics</th><th>AR</th><th>FUR</th><th>RGB</th><th>Einordnung</th></tr></thead>
   <tbody>{filtered.filter(x=>x.status!=='rejected').map(x=><tr key={x.id}>
    <td>{x.label||x.set_slug}</td><td>{x.recorded_displays}</td><td>{x.hits.sar}</td><td>{x.hits.classics}</td><td>{x.hits.ar}</td><td>{x.hits.fur}</td><td>{x.hits.rgb}</td>
    <td><span className={'external-status '+(x.status==='pending'?'external-pending':'')}>Extern eingereicht · {x.status==='pending'?'unter Vorbehalt':'freigegeben'}</span></td>
   </tr>)}</tbody>
  </table></div>}
  <p className="subtle">Nur vollständig erfasste garantierte Hits werden für die reguläre Display-Quote berücksichtigt. Externe Ziehungen werden in dieser Übersicht als separate Herkunft geführt und nicht stillschweigend mit den persönlichen FUR/RGB-Raten vermischt.</p>
 </section>;
}
export function GuestReview({version,run}:{version:number;run:(fn:()=>Promise<void>)=>Promise<void>}){
 const {items,error}=useGuestSubmissions(version);
 const pending=items.filter(x=>x.status==='pending');
 async function review(id:string,status:'approved'|'rejected'){
  if(!window.confirm(status==='approved'?'Externe Ziehung nach Prüfung freigeben?':'Externe Ziehung ablehnen?'))return;
  await run(async()=>{
   const r=await supabase.from('app_guest_submissions').update({status}).eq('id',id).select('id,status').single();
   if(r.error)throw r.error;
  });
 }
 return <section className="card stack">
  <div><h3>Externe Einreichungen prüfen</h3><p className="subtle">
   Diese Ziehungen wurden ohne Anmeldung eingereicht. Sie sind nicht unabhängig verifiziert.
   Bitte plausibilisieren, bevor du sie freigibst.</p></div>
  {error&&<p className="alert">{error}</p>}
  {pending.length===0?<p>Aktuell keine offenen Gast-Einreichungen.</p>:pending.map(x=><div className="guest-review" key={x.id}>
   <div><strong>{x.label||x.set_slug}</strong><p className="subtle">{x.set_slug} · {x.kind} · {x.recorded_displays} erfasste Displays
    · {x.eligible_displays} vollständig · SAR {x.hits.sar} · Classics {x.hits.classics} · AR {x.hits.ar} · FUR {x.hits.fur} · RGB {x.hits.rgb}</p>
    <span className="external-status external-pending">Extern eingereicht · unter Vorbehalt</span></div>
   <div className="actions"><button onClick={()=>void review(x.id,'approved')}>Freigeben</button>
    <button className="secondary" onClick={()=>void review(x.id,'rejected')}>Ablehnen</button></div>
  </div>)}
 </section>;
}
