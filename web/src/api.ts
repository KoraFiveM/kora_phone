import type { Api, Bank, Bootstrap, Call, CallHistory, ChatMessage, Comment, Conversation, DeviceData, MailItem, ModerationReport, Photo, Post, Response } from './types';
import { normalizeData } from './types';
import { mockRequest } from './mock';
import { recall, remember } from './lastScreen';
import { photoBody, videoBody } from './chatTokens';
import { starterApps } from './catalog';
declare global { interface Window { GetParentResourceName?: () => string } }
export const isPreview = !window.GetParentResourceName;
export const requestId = () => crypto.randomUUID();
const aliases: Record<string,string> = { uiReady:'phone:ready', close:'phone:close', captureDone:'camera:close' };
export async function nui<T>(route:string, body:unknown={}):Promise<T>{
  if(isPreview) return {ok:true} as T;
  // FiveM's embedded CEF predates AbortSignal.timeout (Chromium 103+); it is undefined there,
  // which used to throw on every request before any fetch was attempted. Fall back to no signal.
  const signal = typeof AbortSignal !== 'undefined' && typeof AbortSignal.timeout === 'function' ? AbortSignal.timeout(33000) : undefined;
  const response=await fetch(`https://${window.GetParentResourceName!()}/${aliases[route]||route}`,{method:'POST',headers:{'Content-Type':'application/json; charset=UTF-8'},body:JSON.stringify(body),signal});
  if(!response.ok) throw new Error('Phone connection unavailable'); return response.json();
}
// Fire-and-forget: the server relays this to whoever is on the other end of the active call.
export function sendSignal(data:Api['videoSignal'][0]):void{ void api('videoSignal',data).catch(()=>undefined) }
type ServerResult<T>={ok:true;data:T}|{ok:false;error?:string|{code?:string;message?:string}};
// Codes the game scripts return, in words a player can act on.
const friendly:Record<string,string>={SCREENSHOT_PROVIDER_UNAVAILABLE:'The camera needs the screenshot-basic resource running',MEDIA_DISABLED:'Photo storage is not set up on this server',CAMERA_NOT_OPEN:'The camera is not ready. Try again.',UPLOAD_FAILED:'The photo could not be uploaded',PLAYER_DEAD:'You cannot use the camera right now',SESSION_CHANGED:'Your phone changed while that was working. Try again.',EMPTY_SERVER_RESPONSE:'The server did not answer. Try again.',INVALID_SERVER_RESPONSE:'The server sent something unexpected. Try again.',MEDIA_TOO_LARGE:'That file is too big',UNSUPPORTED_MEDIA_TYPE:'That kind of file is not supported',VIDEO_UNSUPPORTED:'This server does not take video clips yet',PROVIDER_MISCONFIGURED:'Uploads are not set up correctly on this server',PROVIDER_BEGIN_FAILED:'The media host would not start an upload. Try again later.',UPLOAD_NOT_VERIFIED:'The upload could not be verified',UPLOAD_MISMATCH:'The uploaded file did not match what was expected',UPLOAD_NOT_BOUND:'The upload could not be matched to this phone',PUBLIC_HOST_DENIED:'The media host is not on this server\'s allowlist',UPLOAD_HOST_DENIED:'The upload address is not on this server\'s allowlist',UPLOAD_TOKEN_EXPIRED:'That upload took too long. Try again.','INVALID_UPLOAD_TOKEN':'That upload is no longer valid. Try again.',INVALID_RECEIPT:'The upload receipt was not valid'};
async function server<T=any>(route:string,body:unknown={}):Promise<T>{const r=await nui<ServerResult<T>>(route,body);if(!r.ok){const e=r.error;const text=typeof e==='string'?e:e?.message||e?.code||'Request failed';throw new Error(friendly[text]??text)}return r.data}
const kindOf=(mime?:string,url?:string):'photo'|'video'|undefined=>url?(String(mime||'').startsWith('video/')?'video':'photo'):undefined;
const mapMessage=(m:any):ChatMessage=>({...m,sender_number:String(m.senderNumber||''),created_at:stamp(m.createdAt),media_url:m.mediaUrl||undefined,media_kind:kindOf(m.mediaMime,m.mediaUrl)});
// One file straight to the media host's presigned URL. XHR (not fetch) so the UI can show progress.
function sendFile(url:string,field:string,blob:Blob,tag:string,onProgress?:(fraction:number)=>void):Promise<string>{return new Promise((resolve,reject)=>{
  const form=new FormData();form.append(field,blob,blob.type.startsWith('video/mp4')?'clip.mp4':blob.type.startsWith('video/')?'clip.webm':'photo.jpg');
  if(tag)form.append('metadata',JSON.stringify({qbphoneTicket:tag}));
  const xhr=new XMLHttpRequest();xhr.open('POST',url);xhr.timeout=90000;
  xhr.upload.onprogress=e=>{if(e.lengthComputable)onProgress?.(e.loaded/e.total)};
  xhr.onload=()=>{try{const r=JSON.parse(xhr.responseText);const id=r?.data?.id??r?.receipt;if(xhr.status>=200&&xhr.status<300&&typeof id==='string')return resolve(id)}catch{/* fall through */}reject(new Error('The media host did not accept the upload'))};
  xhr.onerror=()=>reject(new Error('The upload could not reach the media host'));xhr.ontimeout=()=>reject(new Error('The upload took too long'));
  xhr.send(form)})}
// The server hands out a one-use upload ticket, the phone uploads the file, then the server checks what arrived.
async function uploadMedia(p:{blob:Blob;onProgress?:(fraction:number)=>void}){
  const ticket=await server<any>('media:request',{mimeType:(p.blob.type||'').split(';')[0],byteSize:p.blob.size});
  const up=ticket?.upload;
  if(!up||!['direct-upload','multipart-upload'].includes(up.mode)||typeof up.uploadUrl!=='string')throw new Error('This server cannot take uploads from the phone');
  const receipt=await sendFile(up.uploadUrl,String(up.field||'file'),p.blob,typeof up.tag==='string'?up.tag:'',p.onProgress);
  const saved=await server<any>('media:complete',{token:up.token,receipt});
  return{id:Number(saved.id),url:String(saved.publicUrl),kind:kindOf(saved.mimeType,saved.publicUrl)||'photo'}}
const toPhotos=(g:any):Photo[]=>(g?.items||[]).map((x:any)=>({id:String(x.id),url:String(x.publicUrl),created_at:Number(x.createdAt||0)}));
const defaultData=():DeviceData=>normalizeData({settings:{name:'Nothing Phone',volume:.5,scale:1,wallpaper:'qbcore',theme:'qbcore',setupComplete:false},contacts:[],notes:[],photos:[],stations:[],alarms:[]});
let cached:DeviceData=defaultData();
let cachedDeviceId:string|undefined;
const stamp=(v?:number|string)=>typeof v==='number'?new Date(v*1000).toISOString():String(v||new Date().toISOString());
export function adaptBootstrap(raw:Record<string,any>):Bootstrap{
  const id=String(raw.device?.id||'qbphone');
  if(id!==cachedDeviceId){cached=defaultData();cachedDeviceId=id}
  const contacts=Array.isArray(raw.contacts)?raw.contacts.map((c:any)=>({id:Number(c.id),name:String(c.displayName||''),number:String(c.phoneNumber||''),photo:c.photo,favorite:c.isFavorite===1||c.isFavorite===true})):cached.contacts;
  cached=normalizeData({...cached,contacts,notes:raw.items?.notes??cached.notes,alarms:raw.items?.alarms??cached.alarms,stations:raw.items?.stations??cached.stations,settings:{...cached.settings,...(raw.device?.settings||{})},installedApps:(installed??starterApps) as any,customApps:customAppsInstalled});
  const locked=raw.security?.locked===true;return{id,number:String(raw.device?.phoneNumber||''),locked,hasPin:raw.security?.hasPin===true,moderator:raw.moderator===true,transfers:raw.features?.transfers===true,preferences:cached.settings,data:locked?undefined:cached,admin:raw.admin===true,video:raw.features?.video?{iceServers:Array.isArray(raw.features.video.iceServers)?raw.features.video.iceServers:[]}:false,characterName:[raw.character?.firstName,raw.character?.lastName].filter(Boolean).join(' '),flash:raw.features?.flash?{maxSeconds:Number(raw.features.flash.maxSeconds)||15,maxBytes:Number(raw.features.flash.maxBytes)||undefined}:false,
    capabilities:{banking:true,camera:raw.features?.media===true,gallery:true,social:true,classifieds:true,services:true,calculator:true,clock:true,moderation:raw.moderator===true,gps:raw.features?.maps===true,mail:true,notes:true,weather:true,property:raw.features?.property===true,vehicles:raw.features?.garage===true,flash:!!raw.features?.flash,music:true},
    unavailable:{flash:'Video uploads need a media host, which this server has not configured'},locations:Array.isArray(raw.locations)?raw.locations:[],services:[]};
}
async function reload(){
  const value=adaptBootstrap(await server<Record<string,any>>('bootstrap'));
  if(!value.locked){try{cached={...cached,photos:toPhotos(await server('gallery:list',{limit:100}))};value.data=cached}catch{/* the gallery is optional: the rest of the phone still opens */}}
  return value}
// The server names conversation fields differently from the chat screens: map them once, here.
const adaptConversation=(c:any):Conversation=>({...c,kind:c.type==='group'?'group':'direct',name:c.title??null,members:String(c.peerPhoneNumber||''),last_body:c.lastMessagePreview||'',last_kind:kindOf(c.lastMediaMime,c.lastMediaMime)??null,last_number:null,last_at:c.lastMessageAt?stamp(c.lastMessageAt):null});
function adaptCall(v:any):Call{return{id:String(v.id),status:v.status==='rejected'?'declined':v.status,number:String(v.remoteNumber||''),direction:v.direction||'outgoing',deviceId:'qbphone'} as Call}
export const adaptLiveCall = adaptCall;
let queue:Promise<void>=Promise.resolve();
// The server keeps no per-phone app list yet, so installs are remembered in this NUI's storage.
let installed:string[]|undefined=(()=>{try{const v=JSON.parse(recall('installed')??'null');return Array.isArray(v)?v.filter((x:unknown):x is string=>typeof x==='string'):undefined}catch{return undefined}})();
// Same story for custom/addon apps registered by other resources: which ones this player has installed.
let customAppsInstalled:Record<string,boolean>=(()=>{try{const v=JSON.parse(recall('customApps')??'null');return v&&typeof v==='object'?v:{}}catch{return{}}})();
export function api<K extends keyof Api>(action:K,payload:Api[K][0],id=requestId()):Promise<Api[K][1]>{if(isPreview)return mockRequest(action,payload,id);if(action==='uploadMedia')return uploadMedia(payload as any) as Promise<Api[K][1]>;const result=queue.then(()=>execute(action,payload as any,id));queue=result.then(()=>undefined,()=>undefined);return result as Promise<Api[K][1]>}
async function execute(action:keyof Api,p:any,id:string):Promise<any>{switch(action){
  case'refresh':return reload();case'unlock':await server('security:unlock',{pin:p.pin});return reload();case'lock':await server('security:lock',{});return reload();
  case'settings':await server('settings:save',p);cached=normalizeData({...cached,settings:p});return cached;
  case'installApp':{const s=new Set(cached.installedApps||[]);p.installed?s.add(p.app):s.delete(p.app);installed=[...s] as string[];remember('installed',JSON.stringify(installed));cached={...cached,installedApps:[...s] as any};return cached}
  case'contactSave':{const current=p.id?p:cached.contacts.find(c=>c.number===p.number) as any;if(p.remove)await server('contacts:delete',{id:current?.id});else await server(current?.id?'contacts:update':'contacts:create',{id:current?.id,displayName:p.name,phoneNumber:p.number,isFavorite:p.favorite===true,avatarMediaId:Number(cached.photos.find(x=>x.url===p.photo)?.id)||undefined});return(await reload()).data}
  case'history':{const page=await server<any>('calls:history',{limit:50});return(page.items||[]).map((x:any)=>({id:x.id,caller:x.callerNumber,recipient:x.calleeNumber,status:x.status,created_at:stamp(x.startedAt)})) as CallHistory[]}
  case'dial':return adaptCall(await server('calls:start',{to:p.number}));case'answer':return adaptCall(await server('calls:accept',{id:p.id}));case'hangup':await server(p.reject?'calls:reject':'calls:hangup',{id:p.id});return true;
  case'sendMessage':await server('messages:send',{to:p.recipient,body:p.body,clientRequestId:id});return{sent:true};case'messages':throw new Error('Conversation history needs the peer-number repository upgrade');
  case'bank':{const[balance,history]=await Promise.all([server<any>('bank:getData'),server<any>('bank:getTransactions',{limit:50})]);const account=String(balance.number||balance.account);return{balance:balance.balance,account,name:balance.holder||'Personal',activity:(history.activity||[]).map((x:any)=>({...x,created_at:stamp(x.createdAt)})),history:(history.items||[]).map((x:any)=>({id:String(x.id),citizenid:x.direction==='incoming'?String(x.peer||'Phone transfer'):account,recipient:x.direction==='incoming'?account:String(x.peer||'Phone transfer'),amount:Number(x.amount),status:x.status,created_at:stamp(x.createdAt)}))} as Bank}
  case'transfer':{const v=await server<any>('bank:transfer',{to:p.recipient,amount:p.amount,clientRequestId:id});return{status:v.transaction?.status||'completed'}}
  case'capture':{await server('camera:open');await new Promise(r=>setTimeout(r,400));/* let the UI finish hiding so the phone is not in the screenshot */await server('camera:capture');const g=await server<any>('gallery:list',{limit:100});cached={...cached,photos:toPhotos(g)};return cached}
  case'deletePhoto':await server('gallery:delete',{id:Number(p.id)});cached={...cached,photos:cached.photos.filter(x=>x.id!==String(p.id))};return cached;
  case'feed':{if(p.kind==='classifieds'){const q=await server<any>('market:getListings',{limit:30,cursor:p.before});return(q.items||[]).map((x:any)=>({id:x.id,number:x.sellerHandle||x.sellerName||'seller',body:x.title+(x.description?`\n${x.description}`:''),price:x.price,created_at:stamp(x.createdAt),likes:0,comments:0,liked:false,mine:x.isOwner})) as Post[]}const q=await server<any>('social:getFeed',{limit:30,cursor:p.before});return(q.items||[]).map((x:any)=>({id:x.id,number:x.handle||x.displayName,body:x.body,price:0,created_at:stamp(x.createdAt),likes:x.likeCount||0,comments:x.commentCount||0,liked:!!x.liked,mine:x.mine===1||x.mine===true,media_url:x.mediaUrl||undefined,media_kind:kindOf(x.mediaMime,x.mediaUrl)})) as Post[]}
  case'post':if(p.kind==='classifieds'){const lines=String(p.body).split('\n');await server('market:createListing',{title:lines[0].slice(0,80),description:lines.slice(1).join('\n'),category:'other',price:p.price,clientRequestId:id})}else await server('social:createPost',{body:p.body,mediaId:p.mediaId,clientRequestId:id});return true;
  case'markSold':await server('market:markSold',{id:p.id});return true;
  case'contactSeller':await server('market:contactSeller',{id:p.id,message:p.message,clientRequestId:id});return true;
  case'reportListing':await server('social:report',{targetType:'listing',targetId:p.id,reason:p.reason,details:p.details});return true;
  case'moderationQueue':{const q=await server<any>('moderation:getQueue',{status:p.status||'open',limit:50});return(q.items||[]).map((x:any)=>({id:x.id,targetType:x.targetType,targetId:x.targetId,reason:x.reason,details:x.details||'',status:x.status,createdAt:stamp(x.createdAt),snapshot:x.snapshot||{}})) as ModerationReport[]}
  case'moderationResolve':await server('moderation:resolve',{reportId:p.reportId,action:p.action,note:p.note});return true;
  case'removePost':await server(p.kind==='flash'?'social:deletePost':'market:removeListing',{id:p.id});return true;case'like':await server('social:toggleLike',{postId:p.id,liked:p.liked});return true;
  case'comments':{const q=await server<any>('social:getComments',{postId:p.id,limit:50});return(q.items||[]).map((x:any)=>({id:x.id,number:x.handle||x.displayName,body:x.body,created_at:stamp(x.createdAt)})) as Comment[]}
  case'comment':await server('social:createComment',{postId:p.id,body:p.body,clientRequestId:id});return true;
  case'removeComment':await server('social:deleteComment',{id:p.id});return true;
  case'conversations':{const q=await server<any>('messages:getConversations',{limit:50,cursor:p.before,cursorId:p.cursorId});return(q.items||q||[]).map(adaptConversation) as Conversation[]}
  case'startChat':return adaptConversation(await server<any>('messages:startDirect',{to:p.number}));
  case'conversation':{const q=await server<any>('messages:getPage',{conversationId:p.id,limit:50,cursor:p.before});return(q.items||q||[]).map(mapMessage) as ChatMessage[]}
  case'sendChatMessage':return mapMessage(await server<any>('messages:send',{conversationId:p.conversationId,body:p.body,mediaId:p.mediaId,clientRequestId:id}));
  case'shareToChat':{
    // The clip belongs to whoever posted it, so it travels as a link the receiver's phone plays, plus the caption as text.
    const tooLong=(p.mediaUrl||'').length>1900;
    if(p.mediaUrl&&!tooLong)await server('messages:send',{conversationId:p.conversationId,body:(p.mediaKind==='video'?videoBody:photoBody)(p.mediaUrl),clientRequestId:id});
    const text=[p.body,tooLong?p.mediaUrl:''].filter(Boolean).join('\n').slice(0,1900);
    if(text||!p.mediaUrl)await server('messages:send',{conversationId:p.conversationId,body:text||'A moment from Flash',clientRequestId:p.mediaUrl&&!tooLong?requestId():id});
    return true}
  case'createProfile':await server('social:createAccount',{handle:p.handle,displayName:p.displayName});return true;
  case'markConversationRead':await server('messages:markRead',{conversationId:p.id,messageId:p.messageId});return true;
  case'deleteChatMessage':await server('messages:deleteForSelf',{messageId:p.messageId});return true;
  case'addMember':await server('messages:addMember',{conversationId:p.id,number:p.number});return true;
  case'blocked':return((await server<any>('blocks:list')).items||[]).map((x:any)=>String(x.number));
  case'setBlocked':await server('blocks:set',{number:p.number,blocked:p.blocked});return true;
  case'mailList':{const q=await server<any>('mail:list',{box:p.box,limit:50,cursor:p.before});return(q.items||[]).map((x:any)=>({id:x.id,peer:String(x.peer),subject:x.subject,body:x.body,created_at:stamp(x.createdAt),unread:x.unread===1||x.unread===true,hasAction:x.hasAction===1||x.hasAction===true,canReply:x.canReply!==0&&x.canReply!==false})) as MailItem[]}
  case'mailSend':await server('mail:send',{to:p.to,subject:p.subject,body:p.body,clientRequestId:id});return true;
  case'mailAccept':await server('mail:accept',{id:p.id});return true;case'mailRead':await server('mail:read',{id:p.id});return true;case'mailDelete':await server('mail:delete',{id:p.id});return true;
  case'createGroup':return server('messages:createGroup',{name:p.name,numbers:p.numbers});case'leaveGroup':await server('messages:leaveGroup',{conversationId:p.id});return true;
  case'customApp':{
    const map={...(cached.customApps||{})};
    if('installed' in p) map[p.app]=p.installed===true;
    else if(!map[p.app]) throw new Error('This app is not installed');
    customAppsInstalled=map;remember('customApps',JSON.stringify(map));cached={...cached,customApps:map};return cached}
  case'pin':if(p.pin===''){await server('security:removePin',{currentPin:p.currentPin});return{hasPin:false}}await server('security:setPin',{pin:p.pin,currentPin:p.currentPin});return{hasPin:true};
  case'job':return server('jobs:getData');case'setDuty':return server('jobs:setDuty',{onDuty:p.onDuty});case'jobAction':return server('jobs:runAction',{action:p.action});
  case'property':return server('property:list');case'services':return[];case'vehicles':return server('garage:list');case'weather':return server('weather:get');
  case'notes':case'alarms':case'stations':{const kind=action==='notes'?'note':action==='alarms'?'alarm':'station';const key=action as'notes'|'alarms'|'stations';const{remove,...item}=p;
    if(remove)await server('items:remove',{kind,id:p.id});else await server('items:save',{kind,item});
    const rest=(cached[key] as {id:string}[]).filter(x=>x.id!==p.id);cached={...cached,[key]:remove?rest:[item,...rest]};return cached}
case'waypoint':await server('waypoint',{x:p.x,y:p.y});return true;
    case'videoSignal':await server('calls:signal',{id:p.id,kind:p.kind,sdp:p.sdp,candidate:p.candidate});return true;
  case'wallet':return server('wallet:get');case'showWallet':return server('wallet:show');case'myLocation':return server('location:mine');default:throw new Error(`${String(action)} is not supported by QBPhone v1`)
}}
export type{Response};
