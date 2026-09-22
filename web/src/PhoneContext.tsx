import { createContext, useContext, useEffect, useState } from 'react';
import type { AppId, Bootstrap, Call, DeviceData } from './types';
export interface PhoneContextValue {
  device: Bootstrap; data: DeviceData; updateData: (data: DeviceData) => void;
  navigate: (app: AppId, target?: string) => void; notify: (message: string) => void;
  run: (work: () => Promise<void>) => Promise<void>; busy: boolean;
  setCall: (call?: Call) => void; setHasPin: (value: boolean) => void; revision: number;
}
export const PhoneContext = createContext<PhoneContextValue>(null!);
export const usePhone = () => useContext(PhoneContext);
export function useLoad<T>(load: () => Promise<T>, dependencies: unknown[]) {
  const [value, setValue] = useState<T>();
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [version, setVersion] = useState(0);
  useEffect(() => {
    let mounted = true;
    setLoading(true); setError('');
    load().then(result => { if (mounted) setValue(result); }).catch(e => { if (mounted) setError(e instanceof Error ? e.message : 'Could not load this app'); }).finally(() => { if (mounted) setLoading(false); });
    return () => { mounted = false; };
    // Callers supply the values their loader depends on.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...dependencies, version]);
  return { value, setValue, error, loading, refresh: () => setVersion(v => v + 1) };
}
export function LoadState({ loading, error, retry }: { loading: boolean; error: string; retry: () => void }) {
  if (error) return <div className="load-error" role="alert"><p>{error}</p><button className="text-button" onClick={retry}>Try again</button></div>;
  if (loading) return <p className="loading" role="status">Connecting<span>···</span></p>;
  return null;
}
