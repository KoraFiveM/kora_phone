import { ShieldCheck } from 'lucide-react';
import { api } from '../../api';
import { LoadState,useLoad,usePhone } from '../../core/PhoneContext';
import type { JobData } from '../../types';

type Grade = JobData['job']['grade'];
const text = (value: unknown): string => typeof value === 'string' && value ? value : '';
/** kora_core grades are one-based and carry a name; older payloads send a number plus gradeLabel. */
function gradeText(job: { grade: Grade; gradeLabel?: string }): string {
    const grade = job.grade;
    if (typeof grade === 'object' && grade !== null) {
        return text(grade.label) || text(grade.name) || `Grade ${typeof grade.level === 'number' ? grade.level : ''}`.trim();
    }
    return job.gradeLabel || `Grade ${grade}`;
}
export function ServicesScreen() {
  const { run, busy, notify } = usePhone();
  const work = useLoad(() => api('job', {}), []);
  const job = work.value?.job;
  return <><div className="intro-card"><ShieldCheck size={28} /><h2>Your work.<br />In one place.</h2><p>Your job status and the actions your role allows.</p></div><LoadState {...work} retry={work.refresh} />{job && <section className="panel"><span className="section-label">CURRENT ROLE</span><h2>{job.label || job.name}</h2><p className="muted">{gradeText(job)} · {job.onDuty ? 'On duty' : 'Off duty'}</p><button className="primary" disabled={busy} onClick={() => run(async()=>{await api('setDuty',{onDuty:!job.onDuty});notify(!job.onDuty?'You are on duty':'You are off duty');work.refresh();})}>{job.onDuty?'Go off duty':'Go on duty'}</button></section>}{work.value?.actions?.map(action=><button className="panel" style={{width:'100%',textAlign:'left'}} key={action.id} disabled={busy} onClick={()=>run(async()=>{await api('jobAction',{action:action.id});notify(`${action.label} completed`);})}><strong>{action.label}</strong></button>)}</>;
}
