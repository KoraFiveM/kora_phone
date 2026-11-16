import {
    createContext,
    useCallback,
    useContext,
    useEffect,
    useMemo,
    useRef,
    useState,
    type ReactNode,
} from 'react';
import { createPhoneClient, type PhoneClient, type PhoneClientOptions } from './client.js';
import type { InitPayload, Json, ThemeState } from './protocol.js';

interface PhoneContextValue {
    client: PhoneClient;
    init: InitPayload | null;
    theme: ThemeState | null;
    error: Error | null;
}

const PhoneContext = createContext<PhoneContextValue | null>(null);

export interface PhoneProviderProps {
    children: ReactNode;
    client?: PhoneClient;
    options?: PhoneClientOptions;
    /** Rendered until the init handshake completes. */
    fallback?: ReactNode;
}

export function PhoneProvider({ children, client, options, fallback = null }: PhoneProviderProps) {
    const owned = useRef<PhoneClient | null>(null);
    if (!client && !owned.current) owned.current = createPhoneClient(options);
    const active = client ?? (owned.current as PhoneClient);
    const [init, setInit] = useState<InitPayload | null>(active.init);
    const [theme, setTheme] = useState<ThemeState | null>(active.theme);
    const [error, setError] = useState<Error | null>(null);

    useEffect(() => {
        let alive = true;
        active
            .ready()
            .then((value) => {
                if (!alive) return;
                setInit(value);
                setTheme(active.theme);
            })
            .catch((err: unknown) => {
                if (alive) setError(err instanceof Error ? err : new Error(String(err)));
            });
        const off = active.onTheme((next) => setTheme(next));
        return () => {
            alive = false;
            off();
        };
    }, [active]);

    useEffect(
        () => () => {
            if (owned.current) owned.current.destroy();
        },
        [],
    );

    const value = useMemo(() => ({ client: active, init, theme, error }), [active, init, theme, error]);
    return <PhoneContext.Provider value={value}>{init ? children : fallback}</PhoneContext.Provider>;
}

export function usePhone(): PhoneClient & { init: InitPayload | null; error: Error | null } {
    const ctx = useContext(PhoneContext);
    if (!ctx) throw new Error('usePhone must be used inside <PhoneProvider>');
    return Object.assign(Object.create(ctx.client) as PhoneClient, {
        init: ctx.init,
        error: ctx.error,
    });
}

export function useTheme(): ThemeState | null {
    const ctx = useContext(PhoneContext);
    if (!ctx) throw new Error('useTheme must be used inside <PhoneProvider>');
    return ctx.theme;
}

export interface CallbackState<TOut> {
    data: TOut | null;
    loading: boolean;
    error: Error | null;
}

export function usePhoneCallback<TIn = unknown, TOut = unknown>(name: string) {
    const ctx = useContext(PhoneContext);
    if (!ctx) throw new Error('usePhoneCallback must be used inside <PhoneProvider>');
    const { client } = ctx;
    const [state, setState] = useState<CallbackState<TOut>>({ data: null, loading: false, error: null });
    const call = useCallback(
        async (payload?: TIn): Promise<TOut> => {
            setState((s) => ({ ...s, loading: true, error: null }));
            try {
                const data = await client.callback<TIn, TOut>(name, payload);
                setState({ data, loading: false, error: null });
                return data;
            } catch (err) {
                const error = err instanceof Error ? err : new Error(String(err));
                setState((s) => ({ ...s, loading: false, error }));
                throw error;
            }
        },
        [client, name],
    );
    return { ...state, call };
}

export function usePhoneStorage<T extends Json = Json>(key: string) {
    const ctx = useContext(PhoneContext);
    if (!ctx) throw new Error('usePhoneStorage must be used inside <PhoneProvider>');
    const { client } = ctx;
    const [value, setLocal] = useState<T | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<Error | null>(null);

    useEffect(() => {
        let alive = true;
        setLoading(true);
        client.storage
            .get<T>(key)
            .then((v) => {
                if (alive) setValue(v);
            })
            .catch((err: unknown) => {
                if (alive) setError(err instanceof Error ? err : new Error(String(err)));
            })
            .finally(() => {
                if (alive) setLoading(false);
            });
        function setValue(v: T | null) {
            setLocal(v);
        }
        return () => {
            alive = false;
        };
    }, [client, key]);

    const set = useCallback(
        async (next: T) => {
            await client.storage.set(key, next);
            setLocal(next);
        },
        [client, key],
    );
    const remove = useCallback(async () => {
        await client.storage.remove(key);
        setLocal(null);
    }, [client, key]);
    return { value, loading, error, set, remove };
}
