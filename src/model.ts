export type Profile={id:string;email:string;role:'admin'|'member';status:'pending'|'approved'|'rejected'|'suspended';created_at:string};
export type Rule={slug:string;title:string;displays_per_case:number;cases_per_casecase:number;sar_per_display:number;classics_per_display:number;ar_per_display:number;active:boolean};
export type Rules={displays_per_case:number;cases_per_casecase:number;sar:number;classics:number;ar:number};
export type Opening={id:string;user_id:string;set_slug:string;kind:'display'|'case'|'case_case';label:string;rules:Rules;is_live_public:boolean;status:'active'|'closed';created_at:string;closed_at:string|null};
export type Display={id:string;opening_id:string;ordinal:number;case_no:number;display_no:number};
export type Group={id:string;opening_id:string;mode:'single'|'mixed';opened_boosters:number;status:'active'|'closed';created_at:string;closed_at:string|null};
export type Membership={group_id:string;display_id:string};
export type Category='sar'|'classics'|'ar'|'fur'|'rgb';
export type Hit={id:string;group_id:string;category:Category;created_at:string};
export type Detail={opening:Opening;displays:Display[];groups:Group[];memberships:Membership[];hits:Hit[]};
export const categories:Category[]=['sar','classics','ar','fur','rgb'];
export const names:Record<Category,string>={sar:'SAR',classics:'Classics',ar:'AR',fur:'FUR',rgb:'RGB'};
export const units={display:'Display',case:'Case',case_case:'Case-Case'};
export function target(r:Rules,n:number,c:Category):number|null{return c==='fur'||c==='rgb'?null:r[c]*n;}
export function hits(items:Hit[],c:Category){return items.filter(h=>h.category===c).length;}
export function complete(d:Detail,g:Group){if(g.status!=='closed')return false;const n=d.memberships.filter(m=>m.group_id===g.id).length;return n>0&&(['sar','classics','ar'] as Category[]).every(c=>hits(d.hits.filter(h=>h.group_id===g.id),c)===target(d.opening.rules,n,c));}
export function displayLabel(d:Display){return 'Case '+d.case_no+' · Display '+d.display_no;}
